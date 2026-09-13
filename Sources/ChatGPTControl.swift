import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import Speech


enum ChatGPTControl {
    // The "ChatGPT" desktop app currently ships as the Codex app. Older builds used com.openai.chat.
    static let bundleIdentifiers = ["com.openai.codex", "com.openai.chat"]

    private static let abortLock = NSLock()
    private static var abortRequested = false
    static var submissionInProgress = false // accessed only on the command queue

    static func prepareSubmission() {
        abortLock.lock(); defer { abortLock.unlock() }
        abortRequested = false
    }
    static func requestAbort() {
        abortLock.lock(); defer { abortLock.unlock() }
        abortRequested = true
    }
    static func checkSubmissionCancellation() throws {
        abortLock.lock()
        let cancelled = abortRequested
        abortLock.unlock()
        if submissionInProgress && cancelled {
            throw Failure(number: -30, message: "BREAK로 제출 준비를 중단함")
        }
    }

    // Number of trailing "submit" tokens Bosun itself heard for the current command (set before run()).
    static var spokenCommandCount = 0

    // Exact spellings ChatGPT has produced for the spoken "submit". Checked before the phonetic rule.
    static let knownSubmitWords: Set<String> = [
        "submit", "서브밋", "서브미", "써브미", "섭미", "서브미트", "섭밋", "서밋", "썹밋", "서블릿", "서브밑", "써밋",
        "섬밋", "써브밋", "서브멧", "서브릿", "섭미트", "서브밋트"
    ]

    // Korean prefixes that only ever come from a spoken "submit" at the end of a Korean sentence.
    static let submitPrefixes = ["서브", "써브", "섭", "썹", "서밋", "써밋"]

    // Timing for the Submit sequence. The transcript timeout grows with the recording length:
    // 20 s base + half the dictation length, capped at 120 s.
    static let transcriptTimeoutBase: TimeInterval = 20
    static let transcriptTimeoutMax: TimeInterval = 120
    static var recordingStartedAt: Date?
    static var transcriptTimeout: TimeInterval {
        guard let started = recordingStartedAt else { return transcriptTimeoutBase }
        let length = Date().timeIntervalSince(started)
        return min(transcriptTimeoutMax, transcriptTimeoutBase + length * 0.5)
    }
    static let pollInterval: TimeInterval = 0.25
    static let stableWindow: TimeInterval = 1.0      // transcript must stay unchanged this long
    static let composerReadyTimeout: TimeInterval = 10
    static let submitConfirmTimeout: TimeInterval = 6
    static let deleteAttempts = 3

    // Placeholder strings the text area reports as its value when it is actually empty.
    // Also used to recognise the text area itself: its AXDescription is the placeholder in every state.
    static let placeholders: Set<String> = ["Work with ChatGPT", "ChatGPT로 Work 시작", "무엇이든 요청하세요", "무엇이든 물어보세요", "Ask anything", "Message ChatGPT", "메시지 ChatGPT"]

    static func isEmptyOrPlaceholder(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || placeholders.contains(trimmed)
    }

    // MARK: Label classification (Korean UI verified; English guesses kept as fallbacks)

    static func isMicStartLabel(_ s: String) -> Bool {
        let l = s.lowercased()
        if isMicStopLabel(l) || isCancelLabel(l) || l.contains("transcrib") || l.contains("채팅") || l.contains("chat") { return false }
        return l == "음성 입력" || l.contains("음성 입력") || l.contains("dictat") || l.contains("voice input")
    }

    static func isMicStopLabel(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("중지") || l.contains("정지") || l.contains("stop")
    }

    static func isCancelLabel(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("취소") || l.contains("cancel")
    }

    // "보내기" only. "받아쓰고 보내기" (transcribe and send) is deliberately excluded.
    static func isSendLabel(_ s: String) -> Bool {
        let l = s.lowercased()
        if l.contains("받아쓰") || l.contains("transcrib") { return false }
        return l == "보내기" || l.hasPrefix("보내기") || l == "send" || l.hasPrefix("send ")
    }

    // MARK: Locating the app and the composer

    static func targetApp() -> NSRunningApplication? {
        for id in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return app }
        }
        return NSWorkspace.shared.runningApplications.first { $0.localizedName == "ChatGPT" }
    }

    static func window(of app: NSRunningApplication) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        if let w = AX.element(appEl, kAXFocusedWindowAttribute as String) { return w }
        return AX.elements(appEl, kAXWindowsAttribute as String).first
    }

    // Anchor: the (usually only) AXTextArea whose description is the composer placeholder.
    // Then climb up to 4 levels until a subtree holds a row of at least 3 buttons; assign slots
    // by label first, by x-order as the locale-independent fallback.
    static func findComposer() throws -> Composer {
        guard let app = targetApp() else { throw Failure(number: -10, message: "ChatGPT(Codex) 앱이 실행 중이 아님") }
        guard let win = window(of: app) else { throw Failure(number: -11, message: "ChatGPT 창을 찾을 수 없음") }

        let all = AX.descendants(win)
        let areas = all.filter { AX.role($0) == "AXTextArea" }
        guard let textArea = areas.first(where: { placeholders.contains(AX.description($0)) }) ?? areas.first else {
            throw Failure(number: -12, message: "입력 텍스트 영역을 찾을 수 없음")
        }

        var root = textArea
        for _ in 0..<4 {
            guard let p = AX.parent(root) else { break }
            root = p
            let buttons = AX.descendants(root, maxDepth: 6).filter { AX.role($0) == "AXButton" }
            guard buttons.count >= 3 else { continue }
            let sorted = buttons.sorted { AX.position($0).x < AX.position($1).x }
            let rowY = AX.position(sorted[sorted.count - 1]).y
            let row = sorted.filter { abs(AX.position($0).y - rowY) < 12 }
            guard row.count >= 3 else { continue }

            let mic = row.first { isMicStartLabel(AX.description($0)) || isMicStopLabel(AX.description($0)) } ?? row[row.count - 2]
            let right = row.first { let d = AX.description($0).lowercased(); return isSendLabel(d) || d.contains("보내기") || d.contains("채팅") || d.contains("send") || d.contains("chat") } ?? row[row.count - 1]
            let left = row.first { let d = AX.description($0).lowercased(); return isCancelLabel(d) || d.contains("추가") || d.contains("add") } ?? row[0]
            return Composer(textArea: textArea, buttons: [.left: left, .mic: mic, .right: right])
        }
        throw Failure(number: -13, message: "컴포저 버튼 줄을 찾을 수 없음 (텍스트 영역은 있음)")
    }

    // MARK: Reporting

    static var stepReporter: ((String) -> Void)?

    static let stepLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("Bosun-steps.log")

    static func report(_ text: String) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date())) KST] \(text)"
        stepReporter?(line)
        if let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: stepLogURL) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: stepLogURL)
            }
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let number: Int
        let message: String
        var description: String { "(\(number)) \(message)" }
    }

    // Serial queue so commands never overlap.
    static let queue = DispatchQueue(label: "com.jcutplus.bosun.ax", qos: .userInitiated)

    // MARK: Commands

    private static var activeLatency: LatencyTrace? // Serial command queue only.

    static func press(_ slot: Slot, of composer: Composer, why: String) throws {
        guard let app = targetApp(), let button = composer.button(slot),
              AX.bool(button, kAXEnabledAttribute as String) else {
            throw Failure(number: -14, message: "클릭 가능한 버튼 없음")
        }
        activeLatency?.mark("focus_start")
        app.activate(options: [])
        guard AX.focus(button) else { throw Failure(number: -15, message: "버튼 초점 설정 실패") }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if app.isActive, let focused = AX.element(appElement, kAXFocusedUIElementAttribute as String), CFEqual(focused, button) {
                report("\(why): '\(composer.label(slot))' keyboard activation")
                try checkSubmissionCancellation()
                activeLatency?.mark("key_post_start")
                postKey(49)
                activeLatency?.mark("key_post_end")
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw Failure(number: -15, message: "버튼 초점을 확인할 수 없어 실행하지 않음")
    }

    /// AXPress may return success without a state transition in the target app.
    static func recordingStateMatches(
        _ expected: Bool, timeout: TimeInterval? = nil,
        now: () -> Date = { Date() },
        pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        state: () -> (recording: Bool, canCancel: Bool)? = {
            guard let current = try? findComposer() else { return nil }
            return (current.isRecording, current.canCancel)
        }
    ) -> Bool {
        // Stopping can hide the composer while long audio is transcribed.
        // Keep startup bounded, but allow the same recording-based budget used for transcription.
        let deadline = now().addingTimeInterval(timeout ?? (expected ? 3 : transcriptTimeout))
        while now() < deadline {
            if (try? checkSubmissionCancellation()) == nil { return false }
            if let current = state(), current.recording == expected, !expected || current.canCancel { return true }
            pause(0.1)
        }
        return false
    }

    static func pressRecordingControl(_ slot: Slot, expected: Bool, why: String) throws {
        let current = try findComposer()
        activeLatency?.mark("composer_refreshed")
        try press(slot, of: current, why: why)
        guard recordingStateMatches(expected, timeout: slot == .mic && !expected ? transcriptTimeout : 3) else {
            try checkSubmissionCancellation()
            throw Failure(number: -18, message: "버튼 실행 후 녹음 상태 변화 없음")
        }
    }

    static func run(_ command: VoiceCommand, latency: LatencyTrace? = nil) throws {
        activeLatency = latency
        defer { latency?.mark("run_exit"); activeLatency = nil }
        if ![.undo, .home, .end].contains(command) { invalidateRestore() }
        switch command {
        case .record:
            let c = try findComposer()
            activeLatency?.mark("composer_found")
            report("Record: \(c.summary)")
            if c.isRecording { report("Record 무시: 이미 녹음 중"); return }
            guard isMicStartLabel(c.label(.mic)) else { throw Failure(number: -16, message: "마이크 버튼 라벨이 예상과 다름 '\(c.label(.mic))'") }
            try pressRecordingControl(.mic, expected: true, why: "Record")
            activeLatency?.mark("recording_confirmed")
            recordingStartedAt = Date()
            report("Record 완료")

        case .stop:
            _ = try finishDictation(command: .stop)
            report("Stop 완료")

        case .cancel:
            let c = try findComposer()
            if c.isRecording {
                guard c.canCancel else { throw Failure(number: -17, message: "취소 버튼을 찾을 수 없음") }
                try pressRecordingControl(.left, expected: false, why: "Cancel")
            }
            recordingStartedAt = nil
            try removeCommand(.cancel)
            report("Cancel 완료")

        case .clear:
            let c = try findComposer()
            if c.isRecording {
                guard c.canCancel else { throw Failure(number: -17, message: "취소 버튼을 찾을 수 없음") }
                try pressRecordingControl(.left, expected: false, why: "Clear 녹음 취소")
            }
            recordingStartedAt = nil
            let before = stripTrailingCommand(editableText(try readPromptText()), command: .clear, spokenCount: spokenCommandCount).text
            try focusComposer()
            postKey(0, flags: .maskCommand)
            postKey(51)
            guard waitForSubmitted(timeout: 2) else { throw Failure(number: -20, message: "입력창 전체 삭제 확인 실패") }
            try saveDeletion(before: before, after: "")
            report("Clear 완료")

        case .enter, .space:
            _ = try finishDictation(command: command)
            try focusComposer()
            let before = editableText(try readPromptText())
            let selection = selectedRange()
            let insertion = command == .enter ? "\n" : " "
            let expected = replacing(before, range: selection, with: insertion)
            if command == .enter { postKey(36, flags: .maskShift) }
            else { postKey(49) }
            Thread.sleep(forTimeInterval: 0.3)
            guard editableText(try readPromptText()) == expected else {
                throw Failure(number: -21, message: "텍스트 삽입 결과 확인 실패")
            }
            report("\(command.title) 완료")

        case .delete:
            _ = try finishDictation(command: .delete)
            let before = editableText(try readPromptText())
            let after = removingLastWord(before)
            guard before != after else { report("Delete: 삭제할 단어 없음"); return }
            try deleteTrailing(count: before.count - after.count)
            guard editableText(try readPromptText()) == after else {
                throw Failure(number: -32, message: "마지막 단어 삭제 확인 실패")
            }
            try saveDeletion(before: before, after: after)
            report("Delete 완료")

        case .home, .end:
            if try findComposer().isRecording { invalidateRestore() }
            _ = try finishDictation(command: command)
            try focusComposer()
            postKey(command == .home ? 126 : 125, flags: .maskCommand)
            Thread.sleep(forTimeInterval: 0.15)
            let expected = command == .home ? 0 : (editableText(try readPromptText()) as NSString).length
            guard selectedRange().location == expected else { throw Failure(number: -22, message: "커서 이동 확인 실패") }
            report("\(command.title) 완료")

        case .undo:
            try restoreDeletion()

        case .abort:
            let c = try findComposer()
            if !c.isRecording && isMicStopLabel(c.label(.right)) {
                try press(.right, of: c, why: "Break 응답 생성 중지")
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    let current = try findComposer()
                    if !isMicStopLabel(current.label(.right)) { report("Break 완료: 응답 생성 중지"); return }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                throw Failure(number: -31, message: "응답 중지 결과 확인 실패")
            }
            report("Break 완료: 제출 중단, 진행 중인 응답 없음")

        case .submit:
            let started = ProcessInfo.processInfo.systemUptime
            do {
                try submitSequence()
            } catch {
                let code = (error as? Failure)?.number ?? 0
                report("Send 실패: code=\(code), elapsed=\(String(format: "%.2f", ProcessInfo.processInfo.systemUptime - started))s")
                throw error
            }
        }
    }

    // Accessed only on the serial command queue. Never invokes native Undo.
    static var savedDeletion: DeletionRestore?
    private static var savedEditor: AXUIElement?
    private static var savedWindow: AXUIElement?
    private static var savedWindowTitle = ""
    static var restoreUnavailableReporter: (() -> Void)?

    static func invalidateRestore() {
        savedDeletion = nil; savedEditor = nil; savedWindow = nil
    }

    static func saveDeletion(before: String, after: String) throws {
        guard before != after, let app = targetApp(), let win = window(of: app) else { return }
        let c = try findComposer()
        guard editableText(c.text) == after else { return }
        savedDeletion = DeletionRestore(before: before, after: after)
        savedEditor = c.textArea
        savedWindow = win
        savedWindowTitle = AX.string(win, kAXTitleAttribute as String)
    }

    static func sameRestoreInput(_ c: Composer) -> Bool {
        guard let editor = savedEditor, CFEqual(editor, c.textArea),
              let app = targetApp(), let win = window(of: app), let previous = savedWindow,
              CFEqual(win, previous), AX.string(win, kAXTitleAttribute as String) == savedWindowTitle else { return false }
        return true
    }

    static func validateRestore() {
        guard let saved = savedDeletion else { return }
        guard let c = try? findComposer(), !c.isRecording, sameRestoreInput(c), editableText(c.text) == saved.after else {
            invalidateRestore(); return
        }
    }

    static func restoreDeletion() throws {
        let c = try findComposer()
        let current = editableText(c.text)
        let replacement = DeletionRestore.consume(&savedDeletion, current: current, sameInput: !c.isRecording && sameRestoreInput(c))
        invalidateRestore()
        guard let replacement = replacement else {
            report("Undo 무시: 복원 가능한 삭제 기록 없음")
            restoreUnavailableReporter?()
            return
        }
        try focusComposer()
        // Revalidate immediately before writing; a mismatch consumes the record without editing.
        guard editableText(try readPromptText()) == current else { restoreUnavailableReporter?(); return }
        postKey(0, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.1)
        let selection = selectedRange()
        let currentLength = (current as NSString).length
        guard currentLength == 0 || (selection.location == 0 && selection.length == currentLength) else {
            throw Failure(number: -33, message: "복원 전 전체 선택 확인 실패")
        }
        postKey(51)
        Thread.sleep(forTimeInterval: 0.15)
        if !replacement.isEmpty {
            let chars = Array(replacement.utf16)
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                throw Failure(number: -33, message: "복원 입력 생성 실패")
            }
            event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            event.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)?.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.3)
        guard editableText(try readPromptText()) == replacement else { throw Failure(number: -33, message: "삭제 내용 복원 확인 실패") }
        report("Undo 완료: 마지막 삭제 한 번 복원")
    }

    // Remove the final whitespace-delimited word and its surrounding trailing whitespace.
    // Leading whitespace and earlier line breaks remain untouched.
    static func removingLastWord(_ text: String) -> String {
        guard let last = text.lastIndex(where: { !$0.isWhitespace }) else { return text }
        let end = text.index(after: last)
        let start = text[..<end].lastIndex(where: { $0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
        var prefix = String(text[..<start])
        while let last = prefix.last, last.isWhitespace { prefix.removeLast() }
        return prefix
    }

    static func editableText(_ text: String) -> String {
        placeholders.contains(text.trimmingCharacters(in: .whitespacesAndNewlines)) ? "" : text
    }

    static func selectedRange() -> NSRange {
        guard let c = try? findComposer() else { return NSRange(location: 0, length: 0) }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(c.textArea, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return NSRange(location: (editableText(c.text) as NSString).length, length: 0)
        }
        var range = CFRange()
        AXValueGetValue(value as! AXValue, .cfRange, &range)
        return NSRange(location: range.location, length: range.length)
    }

    static func replacing(_ text: String, range: NSRange, with insertion: String) -> String {
        let value = text as NSString
        guard range.location >= 0, NSMaxRange(range) <= value.length else { return text + insertion }
        return value.replacingCharacters(in: range, with: insertion)
    }

    static func focusComposer() throws {
        guard let app = targetApp() else { throw Failure(number: -10, message: "대상 앱 없음") }
        let c = try findComposer()
        app.activate(options: [])
        guard AX.focus(c.textArea) else { throw Failure(number: -15, message: "입력창 초점 설정 실패") }
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if app.isActive && isTextAreaFocused() { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw Failure(number: -15, message: "입력창 초점 확인 실패")
    }

    static func finishDictation(command: VoiceCommand) throws -> String {
        let c = try findComposer()
        defer { recordingStartedAt = nil }
        let baseline = c.text
        let wasRecording = c.isRecording
        if wasRecording {
            try pressRecordingControl(.mic, expected: false, why: command.title)
            _ = try waitForTranscript(baseline: baseline, wasRecording: true)
        }
        try removeCommand(command)
        let result = try readPromptText()
        return result
    }

    static func stripTrailingCommand(_ text: String, command: VoiceCommand, spokenCount: Int) -> StripResult {
        guard spokenCount > 0 else { return StripResult(text: text, removed: [], reason: "수동 실행") }
        let aliases: [VoiceCommand: Set<String>] = [
            .undo: ["undo", "언두", "언도"],
            .delete: ["delete", "딜리트", "딜리뜨", "딜리터", "델리트", "딜릿"],
            .submit: ["send", "센드", "샌드", "쎈드", "쌘드", "센트", "샌트"],
            .stop: ["stop", "스톱", "스탑", "스톱프", "정지"],
            .cancel: ["cancel", "캔슬", "캔설", "캔셀", "취소"],
            .clear: ["clear", "클리어"],
            .enter: ["enter", "엔터", "엔타"],
            .abort: ["break", "브레이크", "브레익", "브렉", "브레이커"],
            .space: ["space", "스페이스"], .home: ["home", "홈"], .end: ["end", "엔드", "앤드"]
        ]
        let words = aliases[command] ?? [command.rawValue]
        var remaining = text
        var removed: [String] = []
        for _ in 0..<max(1, text.split(whereSeparator: { $0.isWhitespace }).count) {
            var probe = remaining
            var tokens: [String] = []
            _ = popSuffix(&probe, &tokens)
            guard let token = popLastToken(&probe) else { break }
            let normalized = token.lowercased().trimmingCharacters(in: tokenPunctuation)
            if words.contains(normalized) || CommandSuffix.splitMerged(token).map({ words.contains($0) }) == true {
                tokens.append(token)
            } else if let previous = popLastToken(&probe), words.contains((previous + token).lowercased().trimmingCharacters(in: tokenPunctuation)) {
                tokens.append(previous + " " + token)
            } else { break }
            remaining = probe
            removed += tokens
        }
        guard !removed.isEmpty else { return StripResult(text: text, removed: [], reason: "명령어 없음") }
        while let last = remaining.last, last.isWhitespace || last == "," || last == "、" { remaining.removeLast() }
        return StripResult(text: remaining, removed: removed, reason: "명령어 매칭")
    }

    static func removeCommand(_ command: VoiceCommand) throws {
        let original = try readPromptText()
        let result = stripTrailingCommand(original, command: command, spokenCount: spokenCommandCount)
        report("\(command.title) 명령어 삭제: 감지 \(spokenCommandCount)회, 매칭 \(result.removed.count)개, 삭제 \(original.count - result.text.count)글자")
        guard !result.removed.isEmpty else { return }
        try deleteTrailing(count: original.count - result.text.count)
        let actual = try readPromptText()
        guard actual == result.text || (result.text.isEmpty && isEmptyOrPlaceholder(actual)) else {
            throw Failure(number: -3, message: "명령어 삭제 확인 실패")
        }
    }

    static func readPromptText() throws -> String {
        try findComposer().text
    }

    // MARK: Trailing command removal

    struct StripResult {
        let text: String          // remaining text (always a prefix of the input)
        let removed: [String]     // tokens removed, last first
        let reason: String
    }

    static let tokenPunctuation = CharacterSet(charactersIn: ".,!?。、;:'\"…").union(.whitespacesAndNewlines)

    // Hangul syllable decomposition: (initial, medial, final) indexes, nil for non-Hangul.
    static func jamo(_ ch: Character) -> (Int, Int, Int)? {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1,
              scalar.value >= 0xAC00, scalar.value <= 0xD7A3 else { return nil }
        let code = Int(scalar.value - 0xAC00)
        return (code / 588, (code % 588) / 28, code % 28)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }

    // Does this single token sound like "submit"? Handles English misspellings and Korean transliterations
    // (서브밋, 서브미, 서블릿, 섭밋, 써밋 ...). Korean rule: starts with ㅅ/ㅆ + ㅓ/ㅡ/ㅜ/ㅗ/ㅔ, 2-4 syllables,
    // and either ends with a ㅅ/ㅆ/ㅌ/ㄷ/ㅈ/ㅊ final, ends with 트, or begins with a known submit prefix
    // (서브미 has no final consonant and slipped through the old rule).
    static func isSubmitLike(_ raw: String) -> Bool {
        let word = raw.lowercased().trimmingCharacters(in: tokenPunctuation)
        guard !word.isEmpty else { return false }
        if knownSubmitWords.contains(word) { return true }
        if word.allSatisfy({ $0.isASCII }) {
            return levenshtein(word, "submit") <= 2 || (word.hasPrefix("sub") && word.count <= 8)
        }
        let chars = Array(word)
        guard chars.count >= 2, chars.count <= 4 else { return false }
        if submitPrefixes.contains(where: { word.hasPrefix($0) }) { return true }
        guard let first = jamo(chars[0]), let last = jamo(chars[chars.count - 1]) else { return false }
        let initialSieot = [9, 10]                 // ㅅ ㅆ
        let openVowels = [4, 18, 13, 8, 5]         // ㅓ ㅡ ㅜ ㅗ ㅔ
        let closingFinals = [19, 20, 25, 7, 22, 23] // ㅅ ㅆ ㅌ ㄷ ㅈ ㅊ
        guard initialSieot.contains(first.0), openVowels.contains(first.1) else { return false }
        if closingFinals.contains(last.2) { return true }
        return chars[chars.count - 1] == "트"
    }

    // Looser test used only as a fallback: one of the two shape conditions is enough (e.g. 사밋, 서빗, 스밑).
    static func isSubmitHalfLike(_ raw: String) -> Bool {
        let word = raw.lowercased().trimmingCharacters(in: tokenPunctuation)
        let chars = Array(word)
        guard chars.count >= 2, chars.count <= 4 else { return false }
        if word.allSatisfy({ $0.isASCII }) { return levenshtein(word, "submit") <= 3 }
        guard let first = jamo(chars[0]), let last = jamo(chars[chars.count - 1]) else { return false }
        let startsLikeSu = [9, 10].contains(first.0)
        let endsLikeMit = [19, 20, 25, 7, 22, 23].contains(last.2) || chars[chars.count - 1] == "트"
        return startsLikeSu || endsLikeMit
    }

    // Pops the last whitespace-separated token off `text` (trailing whitespace ignored). Returns nil when empty.
    static func popLastToken(_ text: inout String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let start = trimmed.lastIndex(where: { $0.isWhitespace }).map { trimmed.index(after: $0) } ?? trimmed.startIndex
        let token = String(trimmed[start...])
        text = String(trimmed[..<start])
        return token
    }

    // If the last token is the confirmation suffix ("one" / 원 ...), remove it. Returns true when removed.
    static func popSuffix(_ remaining: inout String, _ removed: inout [String]) -> Bool {
        var probe = remaining
        guard let token = popLastToken(&probe), CommandSuffix.matches(token) else { return false }
        removed.append(token)
        remaining = probe
        return true
    }

    // Remove trailing "<submit> one" pairs. The suffix is optional (ChatGPT may drop or merge it).
    // Greedy while tokens match, capped at spokenCount + 1.
    // If nothing matches phonetically, fall back to removing the last spokenCount word(s), since Submit was spoken.
    static func stripTrailingCommand(_ text: String, spokenCount: Int) -> StripResult {
        var remaining = text
        var removed: [String] = []
        let cap = max(spokenCount, 1) + 1
        var reason = "발음 유사 매칭"
        var commandsRemoved = 0
        while commandsRemoved < cap {
            _ = popSuffix(&remaining, &removed)
            var probe = remaining
            guard let token = popLastToken(&probe) else { break }
            if isSubmitLike(token) || (CommandSuffix.splitMerged(token).map { isSubmitLike($0) } ?? false) {
                removed.append(token)
                remaining = probe
                commandsRemoved += 1
                continue
            }
            // Split transliteration such as "서브 밋": try the last two tokens joined.
            var probe2 = probe
            if let previous = popLastToken(&probe2), isSubmitLike(previous + token) {
                removed.append(previous + " " + token)
                remaining = probe2
                commandsRemoved += 1
                continue
            }
            break
        }
        if commandsRemoved == 0 && spokenCount > 0 {
            // Submit was definitely spoken; accept a looser shape match for the last word only.
            var probe = remaining
            if let token = popLastToken(&probe), isSubmitHalfLike(token) || (CommandSuffix.splitMerged(token).map { isSubmitHalfLike($0) } ?? false) {
                reason = "폴백: 느슨한 발음 매칭"
                removed.append(token)
                remaining = probe
            } else {
                reason = "매칭 실패: 아무것도 지우지 않음"
            }
        }
        // Drop a dangling comma/space left before the removed token, but keep sentence-final punctuation.
        while let lastChar = remaining.last, lastChar.isWhitespace || lastChar == "," || lastChar == "、" {
            remaining.removeLast()
        }
        return StripResult(text: remaining, removed: removed, reason: reason)
    }

    // MARK: Keystrokes (used only for the deletion step; presses go through AX)

    static func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // Focus the text area, move the caret to the end, delete `count` characters.
    static func deleteTrailing(count: Int) throws {
        try focusComposer()
        postKey(125, flags: .maskCommand)          // cmd+down: caret to end
        Thread.sleep(forTimeInterval: 0.1)
        for _ in 0..<count { postKey(51) }          // backspace
        Thread.sleep(forTimeInterval: 0.15)
    }

    static func isComposerReady() -> Bool {
        (try? findComposer().canSend) ?? false
    }

    static func isTextAreaFocused() -> Bool {
        (try? findComposer().textAreaFocused) ?? false
    }

    // Poll until the text area holds real text (not empty, not the placeholder) that has not changed for `stableWindow`.
    // `baseline` is the value read before the stop click; the transcript must differ from it unless the baseline
    // was already real text (live transcription shown while recording).
    static func waitForTranscript(
        baseline: String, wasRecording: Bool,
        now: () -> Date = { Date() },
        pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        readText: () throws -> String = { try readPromptText() },
        ready: () -> Bool = { isComposerReady() }
    ) throws -> String {
        let timeout = transcriptTimeout
        let deadline = now().addingTimeInterval(timeout)
        // If we just stopped a recording, the transcript is appended to whatever was in the box,
        // so the value must change. Only a Submit without recording may pass the box as-is.
        let baselineIsText = !wasRecording && !isEmptyOrPlaceholder(baseline)
        var previous = ""
        var unchangedSince = now()
        while now() < deadline {
            try checkSubmissionCancellation()
            pause(pollInterval)
            let current = (try? readText()) ?? ""
            // A stable partial transcript is not completion: wait for the send-ready UI too.
            // Reset stability whenever transcription is still busy or the UI cannot be read.
            guard ready() else {
                previous = current
                unchangedSince = now()
                continue
            }
            if current != previous {
                previous = current
                unchangedSince = now()
                continue
            }
            guard !isEmptyOrPlaceholder(current) else { continue }
            guard current != baseline || baselineIsText else { continue }
            if now().timeIntervalSince(unchangedSince) >= stableWindow {
                return current
            }
        }
        throw Failure(number: -1, message: "\(Int(timeout))초 안에 전사 완료와 보내기 준비를 확인하지 못함. 입력을 유지하고 제출하지 않음")
    }

    // Wait until the right slot reads 보내기 (transcription overlay gone, text present).
    static func waitForComposerReady() throws {
        let deadline = Date().addingTimeInterval(composerReadyTimeout)
        while Date() < deadline {
            try checkSubmissionCancellation()
            if isComposerReady() { return }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        let label = (try? findComposer().label(.right)) ?? "?"
        throw Failure(number: -5, message: "\(Int(composerReadyTimeout))초 안에 보내기 준비를 확인하지 못함 (오른쪽 라벨 '\(label)'). 입력을 유지하고 제출하지 않음")
    }

    // Submit = stop recording (if recording) -> wait for transcript -> wait for 보내기 -> delete trailing token(s)
    //          (verified, retried) -> press 보내기 -> confirm the text area emptied (retry once).
    static func submitSequence() throws {
        submissionInProgress = true
        defer { submissionInProgress = false; recordingStartedAt = nil }
        try checkSubmissionCancellation()
        report("Send 시작")

        var c = try findComposer()
        report("0/6 상태: \(c.summary)")
        let baseline = c.text
        let wasRecording = c.isRecording

        if wasRecording {
            try pressRecordingControl(.mic, expected: false, why: "1/6 녹음 정지")
        } else {
            report("1/6 녹음 중이 아님. 정지 생략 (입력창 텍스트로 진행)")
        }

        report("2/6 전사 텍스트 대기 (\(stableWindow)초 안정, 플레이스홀더 제외, 최대 \(Int(transcriptTimeout))초)")
        let transcript = try waitForTranscript(baseline: baseline, wasRecording: wasRecording)
        recordingStartedAt = nil
        report("2/6 전사 확인: '\(transcript.suffix(40))'")
        // waitForTranscript already verified send readiness throughout the stable window.
        let spoken = spokenCommandCount
        let strip = stripTrailingCommand(transcript, command: .submit, spokenCount: spoken)
        let cleaned = strip.text
        let expected = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        report("3/6 삭제 대상 (\(strip.reason), Bosun 감지 \(spoken)회): \(strip.removed) → 끝 \(transcript.count - cleaned.count)글자")
        if expected.isEmpty {
            throw Failure(number: -2, message: "명령어를 제외하면 전사 내용이 비어 있어 제출하지 않음")
        }

        // 4/6 + 5/6: delete and verify, recomputing from the live text each attempt.
        var verified = false
        for attempt in 1...deleteAttempts {
            try checkSubmissionCancellation()
            let live = try readPromptText()
            let liveTrimmed = live.trimmingCharacters(in: .whitespacesAndNewlines)
            if liveTrimmed == expected {
                verified = true
                report("5/6 검증 통과 (시도 \(attempt)): '\(liveTrimmed.suffix(40))'")
                break
            }
            let liveCleaned = stripTrailingCommand(live, command: .submit, spokenCount: spoken).text
            let removeCount = live.count - liveCleaned.count
            guard removeCount > 0 else {
                report("5/6 실패: 현재 텍스트에서 명령어를 찾지 못함 '\(liveTrimmed.suffix(30))'")
                break
            }
            report("4/6 삭제 시도 \(attempt): 텍스트 영역 포커스 → cmd+↓ → backspace \(removeCount)회")
            try deleteTrailing(count: removeCount)
            if !isTextAreaFocused() { report("경고: 텍스트 영역에 포커스가 없음") }
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard verified else {
            let actual = ((try? readPromptText()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(number: -3, message: "명령어 삭제 결과 불일치. 제출하지 않음. 현재: '\(actual.suffix(20))' 기대: '\(expected.suffix(20))'")
        }

        try waitForComposerReady()
        c = try findComposer()
        guard c.canSend else { throw Failure(number: -5, message: "보내기 버튼이 없음 (오른쪽 라벨 '\(c.label(.right))'). 제출하지 않음") }
        try checkSubmissionCancellation()
        try press(.right, of: c, why: "6/6 제출")
        if waitForSubmitted(timeout: submitConfirmTimeout) {
            report("Send 완료: 입력창 비워짐 확인")
            return
        }
        try checkSubmissionCancellation()
        report("6/6 제출 확인 안 됨. 보내기 재시도")
        c = try findComposer()
        guard c.canSend else { throw Failure(number: -4, message: "재시도 시점에 보내기 버튼이 없음 ('\(c.label(.right))')") }
        try checkSubmissionCancellation()
        try press(.right, of: c, why: "6/6 제출 재시도")
        if waitForSubmitted(timeout: submitConfirmTimeout) {
            report("Send 완료 (재시도): 입력창 비워짐 확인")
            return
        }
        throw Failure(number: -4, message: "보내기를 두 번 눌렀지만 입력창이 비워지지 않음")
    }

    // Submission is confirmed when the text area becomes empty.
    static func waitForSubmitted(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            if (try? checkSubmissionCancellation()) == nil { return false }
            if let text = try? readPromptText(), isEmptyOrPlaceholder(text) { return true }
        }
        return false
    }

    static func isAccessibilityTrusted(prompt: Bool) -> Bool { AX.isTrusted(prompt: prompt) }
}

