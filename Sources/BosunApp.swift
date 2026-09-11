import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import Speech


final class BosunApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var diagnosticMenuItem: NSMenuItem?
    private var header: MenuHeaderView?
    private var visibleError: String?
    private let previewMode = CommandLine.arguments.contains("--preview-menu")

    private func updateStatusIcon() {
        guard let button = item?.button else { return }
        button.title = ""
        let symbol = active ? "waveform" : "mic.slash"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bosun")
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.toolTip = "Bosun — " + L10n.text(active ? "음성 명령 대기 중" : "음성 감지 꺼짐")
        button.setAccessibilityLabel(button.toolTip)
        header?.update(active: active)
        if let message = visibleError { header?.showError(message) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        diagnosticMenuItem?.isHidden = !NSEvent.modifierFlags.contains(.option)
        updateStatusIcon()
        if !previewMode { refreshAccessibility(prompt: false) }
    }
    private let status = NSMenuItem(title: L10n.text("감지 꺼짐"), action: nil, keyEquivalent: "")
    private let level = NSMenuItem(title: L10n.text("마이크 입력: —"), action: nil, keyEquivalent: "")
    private let last = NSMenuItem(title: L10n.text("최근 명령: 없음"), action: nil, keyEquivalent: "")
    private let execution = NSMenuItem(title: L10n.text("최근 실행: 없음"), action: nil, keyEquivalent: "")
    private let accessibility = NSMenuItem(title: L10n.text("접근성 권한: 확인 안 됨"), action: nil, keyEquivalent: "")
    private let step = NSMenuItem(title: L10n.text("현재 단계: —"), action: nil, keyEquivalent: "")
    private let heard = NSMenuItem(title: L10n.text("최근 인식: —"), action: nil, keyEquivalent: "")
    private var lastHeardText = ""
    private var lastRejectKey = ""
    // Last word of the previous (finalised) recognition session, so "stop" / "please" split across
    // two sessions by an early finalisation still forms the compound.
    private var carriedWord = ""
    private var carriedAt = Date.distantPast

    // Partial results arrive many times a second; log each distinct rejection once.
    // Goes to the step log and the "최근 인식" line only — never to the menu bar title.
    private func reportRejection(_ key: String, _ message: String) {
        guard key != lastRejectKey else { return }
        lastRejectKey = key
        let reporter = ChatGPTControl.stepReporter
        ChatGPTControl.stepReporter = nil
        ChatGPTControl.report(message + " | 인식: '\(lastHeardText)'")
        ChatGPTControl.stepReporter = reporter
        heard.title = L10n.format("최근 인식: %@", lastHeardText)
    }
    private var toggle: NSMenuItem!
    private var editMonitor: Any?
    private var busy = false
    private var pendingExecutions = 0
    private var beepToggle: NSMenuItem!
    private var loginToggle: NSMenuItem!
    private var autoStartToggle: NSMenuItem!
    private var modeToggle: NSMenuItem!
    private var autoStartEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoStartListening") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoStartListening") }
    }
    private var beepEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "beepEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "beepEnabled") }
    }
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var rotation: Timer?
    private var settle: Timer?
    private var recognitionSignature = ""
    private var previousCommand: VoiceCommand?
    private var meter: Timer?
    private var active = false
    private var tapInstalled = false
    private var generation = 0
    private var lastSegmentEnd: TimeInterval = 0
    private var lastCommandAt = Date.distantPast
    private var lastBufferAt = Date.distantPast
    private var peak: Float = 0
    private var failures = 0
    private var callbackCount = 0
    private var bufferCount = 0
    private var executionCount = 0
    private var lastError = ""
    private var lastExecution = ""
    private let lock = NSLock()
    private let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "HH:mm:ss 'KST'"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: "allCommandBeepMigrated") {
            beepEnabled = true
            UserDefaults.standard.set(true, forKey: "allCommandBeepMigrated")
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()
        let menu = NSMenu()
        menu.delegate = self
        let headerItem = NSMenuItem()
        let headerView = MenuHeaderView()
        header = headerView
        headerItem.view = headerView
        menu.addItem(headerItem)
        menu.addItem(.separator())
        let settings = NSMenu()
        let settingsItem = NSMenuItem(title: L10n.text("설정"), action: nil, keyEquivalent: "")
        settingsItem.submenu = settings
        let diagnostics = NSMenu()
        [status, level, heard, last, execution, step, accessibility].forEach { diagnostics.addItem($0) }
        let diagnosticsItem = NSMenuItem(title: L10n.text("진단"), action: nil, keyEquivalent: "")
        diagnosticsItem.submenu = diagnostics
        diagnosticsItem.isHidden = true
        diagnosticMenuItem = diagnosticsItem
        toggle = NSMenuItem(title: L10n.text("음성 감지 시작…"), action: #selector(toggleListening), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        for command in VoiceCommand.allCases {
            let manual = NSMenuItem(title: command.menuTitle, action: #selector(manualRun(_:)), keyEquivalent: "")
            manual.image = NSImage(systemSymbolName: ["record": "mic", "stop": "stop", "cancel": "xmark", "send": "paperplane", "clear": "trash", "enter": "return", "space": "space", "home": "arrow.up.to.line", "end": "arrow.down.to.line", "break": "stop.circle", "delete": "delete.left", "undo": "arrow.uturn.backward"][command.rawValue]!, accessibilityDescription: nil)
            manual.target = self
            manual.representedObject = command.rawValue
            menu.addItem(manual)
        }
        let dump = NSMenuItem(title: L10n.text("컴포저 상태 확인 (로그)"), action: #selector(dumpComposer), keyEquivalent: "")
        dump.target = self
        diagnostics.addItem(dump)
        let axCheck = NSMenuItem(title: L10n.text("접근성 권한 요청…"), action: #selector(requestAccessibility), keyEquivalent: "")
        axCheck.target = self
        settings.addItem(axCheck)
        beepToggle = NSMenuItem(title: L10n.text("비프음 (Record 인식 · Submit 인식 · 제출 완료)"), action: #selector(toggleBeep), keyEquivalent: "")
        beepToggle.target = self
        beepToggle.state = beepEnabled ? .on : .off
        settings.addItem(beepToggle)
        loginToggle = NSMenuItem(title: L10n.text("로그인 시 자동 실행"), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginToggle.target = self
        settings.addItem(loginToggle)
        if !previewMode { setupLoginItemDefault() }
        autoStartToggle = NSMenuItem(title: L10n.text("실행 시 음성 감지 자동 시작"), action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartToggle.target = self
        autoStartToggle.state = autoStartEnabled ? .on : .off
        settings.addItem(autoStartToggle)
        modeToggle = NSMenuItem(title: CommandMode.current.label, action: #selector(toggleMode), keyEquivalent: "")
        modeToggle.target = self
        settings.addItem(modeToggle)
        ChatGPTControl.stepReporter = { [weak self] line in
            DispatchQueue.main.async {
                self?.step.title = L10n.text("작업 진행 중 · 상세 내용은 로그 참조")
                self?.updateStatusIcon()
            }
        }
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(diagnosticsItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: L10n.text("Bosun 정보"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: L10n.text("종료"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        updateStatusIcon()
        if previewMode { return }
        refreshAccessibility(prompt: false)
        ChatGPTControl.restoreUnavailableReporter = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.beepEnabled else { return }
                if let sound = NSSound(named: NSSound.Name("Basso")) { sound.play() }
                else { NSSound.beep() }
            }
        }
        editMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self = self, !self.busy, ChatGPTControl.targetApp()?.isActive == true else { return }
            if event.type == .keyDown && [123, 124, 125, 126, 115, 119].contains(Int(event.keyCode)) { return }
            // Native typing, paste, clicking another conversation, or starting dictation
            // invalidates the one-shot record even if the user later recreates the same text.
            ChatGPTControl.queue.async { ChatGPTControl.invalidateRestore() }
        }
        meter = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.writeDiagnostics()
            if !self.busy { ChatGPTControl.queue.async { ChatGPTControl.validateRestore() } }
            guard self.active else { return }
            self.lock.lock()
            let elapsed = Date().timeIntervalSince(self.lastBufferAt)
            let amplitude = self.peak
            self.lock.unlock()
            self.level.title = elapsed < 2
                ? String(format: L10n.text("마이크 입력 수신 중: %.0f dBFS"), 20 * log10(max(amplitude, 0.000001)))
                : L10n.text("마이크 입력: 2초 이상 수신 없음")
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        let needsPermissions = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || SFSpeechRecognizer.authorizationStatus() != .authorized
            || !ChatGPTControl.isAccessibilityTrusted(prompt: false)
        if !needsPermissions && autoStartEnabled {
            DispatchQueue.main.async { [weak self] in self?.toggleListening() }
        }
        if needsPermissions {
            DispatchQueue.main.async { [weak self] in
                let alert = NSAlert()
                alert.messageText = L10n.text("Bosun 권한 설정")
                alert.informativeText = L10n.text("마이크, 음성 인식, 손쉬운 사용(접근성) 권한이 필요해. 설정을 시작하면 macOS 권한 안내가 차례로 표시돼. 설정 후에는 메뉴 막대에서만 실행돼.")
                alert.addButton(withTitle: L10n.text("설정 시작"))
                alert.addButton(withTitle: L10n.text("나중에"))
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    self?.refreshAccessibility(prompt: true)
                    self?.toggleListening()
                }
            }
        }
    }

    @discardableResult
    private func refreshAccessibility(prompt: Bool) -> Bool {
        let trusted = ChatGPTControl.isAccessibilityTrusted(prompt: prompt)
        accessibility.title = trusted ? L10n.text("접근성 권한: 허용됨") : L10n.text("접근성 권한: 없음 (시스템 설정 → 손쉬운 사용)")
        header?.setPermissionNeeded(!trusted)
        return trusted
    }

    @objc private func requestAccessibility() {
        refreshAccessibility(prompt: true)
    }

    @objc private func dumpComposer() {
        ChatGPTControl.queue.async {
            do {
                let c = try ChatGPTControl.findComposer()
                ChatGPTControl.report("컴포저: \(c.summary)")
            } catch {
                ChatGPTControl.report("컴포저 탐색 실패: \(error)")
            }
        }
    }

    // Login item via SMAppService (macOS 13+). Default on: registered automatically on first launch
    // unless the user has turned it off from the menu before.
    private func setupLoginItemDefault() {
        let service = SMAppService.mainApp
        if UserDefaults.standard.object(forKey: "loginItemWanted") == nil, service.status != .enabled {
            do { try service.register() } catch { lastError = "login item: \(error.localizedDescription)" }
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        loginToggle.state = status == .enabled ? .on : .off
        loginToggle.title = status == .requiresApproval
            ? L10n.text("로그인 시 자동 실행 (시스템 설정 → 로그인 항목에서 승인 필요)")
            : L10n.text("로그인 시 자동 실행")
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                UserDefaults.standard.set(false, forKey: "loginItemWanted")
            } else {
                try service.register()
                UserDefaults.standard.set(true, forKey: "loginItemWanted")
            }
        } catch {
            lastError = "login item: \(error.localizedDescription)"
            status.title = L10n.format("자동 실행 설정 실패: %@", error.localizedDescription)
        }
        refreshLoginItem()
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc private func toggleBeep() {
        beepEnabled.toggle()
        beepToggle.state = beepEnabled ? .on : .off
    }

    @objc private func toggleMode() {
        CommandMode.current = CommandMode.current == .korean ? .english : .korean
        modeToggle.title = CommandMode.current.label
        if active { beginSession() }   // refresh contextual strings
    }

    @objc private func toggleAutoStart() {
        autoStartEnabled.toggle()
        autoStartToggle.state = autoStartEnabled ? .on : .off
    }

    // Every accepted voice or menu command receives one cue.
    private func beep() {
        guard beepEnabled else { return }
        if let sound = NSSound(named: NSSound.Name("Tink")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    @objc private func manualRun(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = VoiceCommand(rawValue: raw) else { return }
        perform(command, source: L10n.text("수동"))
    }

    private func perform(_ command: VoiceCommand, source: String, spokenCount: Int = 0) {
        if command == .abort { ChatGPTControl.requestAbort() }
        guard !busy || command == .abort else {
            status.title = L10n.format("%@ 대기: 이전 명령 실행 중", command.title)
            return
        }
        if command == .submit { ChatGPTControl.prepareSubmission() }
        pendingExecutions += 1
        visibleError = nil
        beep()
        busy = true
        refreshAccessibility(prompt: false)
        execution.title = L10n.format("최근 실행: %@ 진행 중…", command.title)
        ChatGPTControl.queue.async { [weak self] in
            ChatGPTControl.spokenCommandCount = spokenCount
            let outcome: Result<Void, Error> = Result { try ChatGPTControl.run(command) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingExecutions -= 1
                self.busy = self.pendingExecutions > 0
                let stamp = self.clock.string(from: Date())
                switch outcome {
                case .success:
                    self.lastError = ""
                    self.executionCount += 1
                    self.lastExecution = "\(command.title) ok \(stamp)"
                    self.execution.title = L10n.format("최근 실행: %@ 성공 (%@) · %@", command.title, source, stamp)
                    self.updateStatusIcon()
                case .failure(let error):
                    let text = (error as? ChatGPTControl.Failure)?.description ?? error.localizedDescription
                    self.lastExecution = "\(command.title) fail \(text) \(stamp)"
                    self.lastError = "ax \(text)"
                    self.visibleError = L10n.text("명령 실행 실패 · 권한 확인")
                    self.execution.title = L10n.format("최근 실행: %@ 실패 · %@", command.title, stamp)
                    self.updateStatusIcon()
                }
            }
        }
    }

    private func writeDiagnostics() {
        lock.lock()
        let count = bufferCount
        let amplitude = peak
        let age = Date().timeIntervalSince(lastBufferAt)
        lock.unlock()
        let report: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "active": active, "engineRunning": engine.isRunning,
            "microphoneAuthorization": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
            "speechAuthorization": SFSpeechRecognizer.authorizationStatus().rawValue,
            "accessibilityTrusted": ChatGPTControl.isAccessibilityTrusted(prompt: false),
            "buffers": count, "peak": amplitude, "lastBufferAgeSeconds": age,
            "recognitionCallbacks": callbackCount, "status": status.title,
            "lastCommand": last.title, "executions": executionCount,
            "lastExecution": lastExecution, "error": lastError,
            "sampledAtEpoch": Date().timeIntervalSince1970
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Bosun-diagnostics.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @objc private func toggleListening() {
        if active { stop(); return }
        visibleError = nil
        toggle.isEnabled = false
        status.title = L10n.text("마이크·음성 인식 권한 확인 중")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            guard let self = self else { return }
            guard allowed else {
                DispatchQueue.main.async { self.fail(L10n.text("시스템 설정에서 마이크 접근을 허용해야 함")) }
                return
            }
            SFSpeechRecognizer.requestAuthorization { authorization in
                DispatchQueue.main.async {
                    guard authorization == .authorized else {
                        self.fail(L10n.text("시스템 설정에서 음성 인식을 허용해야 함"))
                        return
                    }
                    guard self.recognizer?.supportsOnDeviceRecognition == true else {
                        self.fail(L10n.text("영어 로컬 인식이 지원되지 않음. 서버 인식으로 전환하지 않음"))
                        return
                    }
                    self.refreshAccessibility(prompt: true)
                    self.active = true
                    self.failures = 0
                    self.toggle.isEnabled = true
                    self.toggle.title = L10n.text("음성 감지 중지")
                    self.beginSession()
                }
            }
        }
    }

    private func beginSession() {
        guard active else { return }
        teardownSession()
        guard recognizer?.isAvailable == true else {
            retry(L10n.text("음성 인식 서비스 사용 불가"))
            return
        }
        generation += 1
        let current = generation
        lastSegmentEnd = 0
        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.requiresOnDeviceRecognition = true
        audioRequest.shouldReportPartialResults = true
        audioRequest.contextualStrings = VoiceCommand.allCases.flatMap {
            CommandMode.current == .korean ? [$0.title] : [$0.title + " please", $0.title]
        }
        audioRequest.taskHint = .confirmation
        request = audioRequest
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail(L10n.text("사용 가능한 마이크 입력 형식이 없음"))
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            audioRequest.append(buffer)
            guard let self = self else { return }
            var amplitude: Float = 0
            if let channel = buffer.floatChannelData?[0] {
                for index in 0..<Int(buffer.frameLength) { amplitude = max(amplitude, abs(channel[index])) }
            }
            self.lock.lock()
            self.bufferCount += 1
            self.peak = amplitude
            self.lastBufferAt = Date()
            self.lock.unlock()
        }
        tapInstalled = true
        task = recognizer?.recognitionTask(with: audioRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.active, self.generation == current else { return }
                if let result = result {
                    self.callbackCount += 1
                    self.failures = 0
                    self.consider(result.bestTranscription.segments, generation: current)
                    if result.isFinal {
                        if let lastSegment = result.bestTranscription.segments.last {
                            self.carriedWord = lastSegment.substring.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                            self.carriedAt = Date()
                        }
                        // Give the last isolated command time to settle before rotating.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            if self.active && self.generation == current { self.beginSession() }
                        }
                    }
                }
                if let error = error {
                    self.lastError = "\((error as NSError).domain):\((error as NSError).code) \(error.localizedDescription)"
                    self.retry(L10n.format("인식 재연결: %@", String((error as NSError).code)))
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            updateStatusIcon()
            status.title = L10n.text("영어 명령 감지 중 · ChatGPT 컴포저 제어 연결됨")
            rotation = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in self?.beginSession() }
        } catch {
            retry(L10n.format("마이크 시작 실패: %@", String((error as NSError).code)))
        }
    }

    private func consider(_ segments: [SFTranscriptionSegment], generation current: Int) {
        guard let tail = segments.last else { settle?.invalidate(); recognitionSignature = ""; return }
        let signature = segments.suffix(2).map { "\($0.timestamp):\($0.substring.lowercased())" }.joined(separator: "|")
        guard signature != recognitionSignature else { return }
        recognitionSignature = signature
        settle?.invalidate()
        let clean: (SFTranscriptionSegment) -> String = {
            $0.substring.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        }
        // Show what the recognizer hears (last 8 words) so misrecognitions can be diagnosed from the menu.
        let tailWords = segments.suffix(8).map { clean($0) }.joined(separator: " ")
        if tailWords != lastHeardText {
            lastHeardText = tailWords
            heard.title = L10n.format("최근 인식: %@", tailWords)
        }
        let command: VoiceCommand
        let word: String
        var spokenCount = 0
        var tailWord = clean(tail)
        var compoundCommand: VoiceCommand?
        var compoundWord = ""
        // Recogniser may return "stop please" as one segment.
        let parts = tailWord.split(separator: " ").map(String.init)
        if parts.count == 2, CommandSuffix.matches(parts[1]), let c = VoiceCommand(rawValue: parts[0]) {
            compoundCommand = c; compoundWord = parts[0]
        } else if CommandSuffix.matches(tailWord) {
            if segments.count >= 2, let c = VoiceCommand(rawValue: clean(segments[segments.count - 2])) {
                compoundCommand = c; compoundWord = clean(segments[segments.count - 2])
            } else if segments.count == 1, Date().timeIntervalSince(carriedAt) < 2.5, let c = VoiceCommand(rawValue: carriedWord) {
                // "<command>" was finalised in the previous session and "please" opened this one.
                compoundCommand = c; compoundWord = carriedWord
                ChatGPTControl.report("복합어 세션 경계 결합: '\(carriedWord)' + '\(tailWord)'")
            }
        }
        if let c = compoundCommand {
            // Compound form "<command> please" — accepted in both modes, no gap requirement.
            command = c
            word = compoundWord
            tailWord = word
            var index = segments.count - 1
            while index >= 1, CommandSuffix.matches(clean(segments[index])), clean(segments[index - 1]) == word {
                spokenCount += 1
                index -= 2
            }
            spokenCount = max(spokenCount, 1)
        } else if CommandMode.current == .korean, let c = VoiceCommand(rawValue: tailWord) {
            // Bare word (Korean mode only): the original detection — isolated trailing word with a gap before it.
            command = c
            word = tailWord
            if segments.count > 1 {
                let previous = segments[segments.count - 2]
                let gap = tail.timestamp - previous.timestamp - previous.duration
                guard gap >= 0.35 else {
                    reportRejection("gap:\(word):\(clean(previous))", "명령 후보 '\(word)' 거부: 앞 단어 '\(clean(previous))' 와 간격 \(String(format: "%.2f", gap))초")
                    return
                }
            }
            for segment in segments.reversed() {
                if clean(segment) == word { spokenCount += 1 } else { break }
            }
        } else {
            if VoiceCommand(rawValue: tailWord) != nil {
                reportRejection("en:\(tailWord)", "명령 후보 '\(tailWord)' 거부: 영어 모드는 '\(tailWord) please' 형태만 인정")
            }
            return
        }
        let end = tail.timestamp + tail.duration
        guard end > lastSegmentEnd else { return }
        settle = Timer.scheduledTimer(withTimeInterval: CommandTiming.settling(command), repeats: false) { [weak self] _ in
            guard let self = self, self.active, self.generation == current else { return }
            self.lastSegmentEnd = end
            guard Date().timeIntervalSince(self.lastCommandAt) >= CommandTiming.cooldown(previous: self.previousCommand, next: command) else { return }
            self.lastCommandAt = Date()
            self.previousCommand = command
            self.last.title = L10n.format("최근 명령: %@ · %@", command.title, self.clock.string(from: Date()))
            self.updateStatusIcon()
            self.status.title = L10n.format("%@ 인식됨 · %@", command.title, command.label)
            self.perform(command, source: L10n.text("음성"), spokenCount: spokenCount)
        }
    }

    private func retry(_ message: String) {
        teardownSession()
        failures += 1
        guard failures <= 5 else { fail(L10n.text("연속 오류로 감지 중지. 메뉴에서 다시 시작해 줘")); return }
        status.title = message
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(min(failures * 2, 10))) { [weak self] in
            guard let self = self, self.active, self.generation == current else { return }
            self.beginSession()
        }
    }

    private func teardownSession() {
        generation += 1
        rotation?.invalidate()
        settle?.invalidate()
        recognitionSignature = ""
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }

    private func stop() {
        active = false
        teardownSession()
        updateStatusIcon()
        status.title = L10n.text("감지 꺼짐")
        level.title = L10n.text("마이크 입력: —")
        toggle.title = L10n.text("음성 감지 시작…")
        toggle.isEnabled = true
    }

    private func fail(_ message: String) {
        stop()
        status.title = message
        visibleError = message
        header?.showError(message)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [:])
    }

    @objc private func sleeping() { stop() }
    @objc private func quitApp() { stop(); NSApp.terminate(nil) }
}

