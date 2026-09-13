import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let samples: [(String, String)] = [
    ("hello submit", "hello"),
    ("안녕하세요 서브밋", "안녕하세요"),
    ("hello submit please", "hello"),
    ("안녕하세요 서브밋 플리즈", "안녕하세요"),
    ("hello world", "hello world"),
    ("", "")
]
for (input, expected) in samples {
    let result = ChatGPTControl.stripTrailingCommand(input, spokenCount: 1)
    expect(result.text == expected, "Transcript regression: \(input) -> \(result.text), expected \(expected)")
}
expect(CommandSuffix.matches("please"), "English suffix")
expect(CommandSuffix.matches("플리즈"), "Korean suffix")
expect(!CommandSuffix.matches("hello"), "Reject unrelated suffix")
expect(VoiceCommand.allCases.count == 12, "Twelve commands")
expect(ChatGPTControl.isEmptyOrPlaceholder("ChatGPT로 Work 시작"), "Current Work placeholder must be empty")
expect(!ChatGPTControl.isEmptyOrPlaceholder("Bosun 전송 테스트"), "Real prompt must not be empty")
print("12 command regression checks passed")

for (command, input, expected) in [
    (VoiceCommand.stop, "본문 스톱", "본문"),
    (.stop, "본문 stop please", "본문"),
    (.cancel, "본문 캔슬", "본문"),
    (.cancel, "본문 cancelplease", "본문"),
    (.enter, "본문 enter please", "본문"),
    (.enter, "본문 엔터", "본문"),
    (.stop, "본문 please", "본문 please"),
    (.cancel, "본문 내용", "본문 내용")
] {
    expect(ChatGPTControl.stripTrailingCommand(input, command: command, spokenCount: 1).text == expected, "Command removal: \(input)")
    expect(ChatGPTControl.stripTrailingCommand(input, command: command, spokenCount: 0).text == input, "Manual preserves text")
}
print("Additional command removal checks passed")
expect(ChatGPTControl.stripTrailingCommand("본문 스탑. 스탑.", command: .stop, spokenCount: 1).text == "본문", "Repeated stop must be removed even when recognition counted once")

for (command, word) in [(VoiceCommand.enter, "엔터"), (.space, "스페이스"), (.home, "홈"), (.end, "엔드")] {
    expect(ChatGPTControl.stripTrailingCommand("본문 " + word, command: command, spokenCount: 1).text == "본문", "Editing command cleanup")
}
expect(VoiceCommand(rawValue: "newline") == nil, "Old newline command retired")

expect(VoiceCommand(rawValue: "redo") == nil, "Redo removed")
expect(CommandTiming.settling(.stop) == 0.18, "Fast normal command")
expect(CommandTiming.settling(.submit) == 0.30, "Submit confirmation delay")
expect(CommandTiming.cooldown(previous: .record, next: .stop) == 0.15, "Different command may follow quickly")
expect(CommandTiming.cooldown(previous: .record, next: .record) == 0.60, "Repeated command protected")

ChatGPTControl.prepareSubmission()
ChatGPTControl.submissionInProgress = true
try ChatGPTControl.checkSubmissionCancellation()
ChatGPTControl.requestAbort()
do { try ChatGPTControl.checkSubmissionCancellation(); fatalError("Abort did not cancel") }
catch let error as ChatGPTControl.Failure { expect(error.number == -30, "Abort cancellation reason") }
ChatGPTControl.submissionInProgress = false
try ChatGPTControl.checkSubmissionCancellation()
ChatGPTControl.prepareSubmission()
print("Abort cancellation checks passed")

expect(VoiceCommand(rawValue: "send") == .submit, "Send recognition")
expect(VoiceCommand(rawValue: "break") == .abort, "Break recognition")
expect(VoiceCommand(rawValue: "submit") == nil && VoiceCommand(rawValue: "abort") == nil, "Old spoken commands removed")
for (command, input, expected) in [
    (VoiceCommand.submit, "본문 센드. 센드.", "본문"),
    (.submit, "본문 send please", "본문"),
    (.submit, "본문 샌드플리즈", "본문"),
    (.submit, "주말에 spend", "주말에 spend"),
    (.submit, "본문 submit", "본문 submit"),
    (.abort, "본문 break please", "본문"),
    (.abort, "본문 브레이크", "본문")
] {
    expect(ChatGPTControl.stripTrailingCommand(input, command: command, spokenCount: 1).text == expected, "Renamed command cleanup: \(input)")
}
print("Send / Break recognition and cleanup checks passed")

for (input, expected) in [("첫 번째 단어", "첫 번째"), ("hello world.  ", "hello"), ("단어", ""), ("", ""), ("  ", "  "), ("앞줄\n둘째 줄 마지막", "앞줄\n둘째 줄"), ("  hello world", "  hello")] {
    expect(ChatGPTControl.removingLastWord(input) == expected, "Delete last word: \(input)")
}
expect(VoiceCommand(rawValue: "delete") == .delete, "Delete recognition")
for word in ["delete please", "딜리트", "딜리트 플리즈"] {
    let cleaned = ChatGPTControl.stripTrailingCommand("본문 마지막 " + word, command: .delete, spokenCount: 1).text
    expect(ChatGPTControl.removingLastWord(cleaned) == "본문", "Delete command cleanup then last word")
}
print("Delete checks passed")

expect(VoiceCommand(rawValue: "undo") == .undo, "Limited Undo dispatch")
expect(ChatGPTControl.removingLastWord(ChatGPTControl.removingLastWord("첫째 둘째 셋째 넷째")) == "첫째 둘째", "Two deletes remove exactly two words")

var saved: DeletionRestore? = DeletionRestore(before: "one two", after: "one")
expect(DeletionRestore.consume(&saved, current: "one", sameInput: true) == "one two", "Restore last deletion")
expect(DeletionRestore.consume(&saved, current: "one two", sameInput: true) == nil, "Restore once only")
saved = DeletionRestore(before: "all", after: "")
expect(DeletionRestore.consume(&saved, current: "", sameInput: true) == "all", "Restore clear")
for (value, same) in [("one\n", true), ("one ", true), ("changed", true), ("one", false)] {
    saved = DeletionRestore(before: "one two", after: "one")
    expect(DeletionRestore.consume(&saved, current: value, sameInput: same) == nil && saved == nil, "Invalidate edited or different input")
}
print("Limited one-shot Undo checks passed")

// Representative English row reproducing the logged Cancel dictation mic selection.
let recordingLabels = ["Cancel dictation", "Stop dictation", "Transcribe and send"]
let selectedMic = recordingLabels.first { ChatGPTControl.isMicStartLabel($0) || ChatGPTControl.isMicStopLabel($0) }
expect(selectedMic == "Stop dictation", "Recording must select Stop dictation, not Cancel dictation")
expect(!ChatGPTControl.isMicStartLabel("Cancel dictation"), "Cancel is never a start mic")
expect(!ChatGPTControl.isMicStartLabel("Transcribe dictation"), "Transcription is never a start mic")
expect(ChatGPTControl.isMicStartLabel("Dictate"), "English record remains supported")
expect(ChatGPTControl.isEmptyOrPlaceholder("\nWork with ChatGPT"), "English Work placeholder is not a transcript")
print("English recording button and placeholder regressions passed")

// Drive the actual transcript polling loop with a delayed final transcription.
// Long dictation can display a stable partial result before the composer is ready.
var simulatedTime: TimeInterval = 0
ChatGPTControl.recordingStartedAt = nil
let completeDictation = String(repeating: "긴 문장 내용 ", count: 100) + "send please"
let delayedTranscript = try ChatGPTControl.waitForTranscript(
    baseline: "", wasRecording: true,
    now: { Date(timeIntervalSince1970: simulatedTime) },
    pause: { simulatedTime += $0 },
    readText: { simulatedTime < 12 ? "일부 전사 내용" : completeDictation },
    ready: { simulatedTime >= 12 }
)
expect(delayedTranscript == completeDictation, "Long dictation: must wait for final ready transcript, otherwise Send cleanup uses stale expected text")
print("Delayed transcript regression passed")

expect(simulatedTime >= 13, "Final transcript needs a full ready stability window")
simulatedTime = 0
let quickTranscript = try ChatGPTControl.waitForTranscript(
    baseline: "", wasRecording: true,
    now: { Date(timeIntervalSince1970: simulatedTime) },
    pause: { simulatedTime += $0 }, readText: { "짧은 문장 send please" }, ready: { true }
)
expect(quickTranscript == "짧은 문장 send please" && simulatedTime <= 1.5, "Short ready input should not incur extra delay")
simulatedTime = 0
do {
    _ = try ChatGPTControl.waitForTranscript(
        baseline: "", wasRecording: true,
        now: { Date(timeIntervalSince1970: simulatedTime) },
        pause: { simulatedTime += $0 }, readText: { "아직 처리 중인 전사" }, ready: { false }
    )
    fatalError("Busy transcription must time out rather than return partial text")
} catch let error as ChatGPTControl.Failure {
    expect(error.number == -1 && simulatedTime >= 20, "Busy timeout must preserve input")
}
simulatedTime = 0
ChatGPTControl.recordingStartedAt = Date().addingTimeInterval(-100)
let longWait = try ChatGPTControl.waitForTranscript(
    baseline: "", wasRecording: true,
    now: { Date(timeIntervalSince1970: simulatedTime) },
    pause: { simulatedTime += $0 },
    readText: { simulatedTime < 35 ? "처리 중" : completeDictation },
    ready: { simulatedTime >= 35 }
)
expect(longWait == completeDictation && simulatedTime >= 36, "Long recording uses extended timeout for final readiness")
ChatGPTControl.recordingStartedAt = nil
print("Short, busy, and extended transcript timing checks passed")

simulatedTime = 0
let stoppedAfterTranscription = ChatGPTControl.recordingStateMatches(
    false,
    now: { Date(timeIntervalSince1970: simulatedTime) },
    pause: { simulatedTime += $0 },
    state: { simulatedTime < 8 ? nil : (recording: false, canCancel: false) }
)
expect(stoppedAfterTranscription, "Long dictation: stop must survive a transcription UI lasting more than 3 seconds")
print("Delayed stop transition regression passed")

simulatedTime = 0
expect(!ChatGPTControl.recordingStateMatches(
    true, now: { Date(timeIntervalSince1970: simulatedTime) },
    pause: { simulatedTime += $0 }, state: { nil }
), "Missing recording start must fail")
expect(simulatedTime < 3.2, "Record startup retains its short timeout")
ChatGPTControl.prepareSubmission()
ChatGPTControl.submissionInProgress = true
ChatGPTControl.requestAbort()
simulatedTime = 0
expect(!ChatGPTControl.recordingStateMatches(
    false, now: { Date(timeIntervalSince1970: simulatedTime) },
    pause: { simulatedTime += $0 }, state: { nil }
), "Break must cancel stop wait")
expect(simulatedTime == 0, "Break must not wait for the timeout")
ChatGPTControl.submissionInProgress = false
ChatGPTControl.prepareSubmission()
print("Recording startup timeout and Break checks passed")
