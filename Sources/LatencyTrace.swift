import Foundation

// Opt-in timing only. No audio or transcription text is stored.
final class LatencyTrace {
    static let enabled = CommandLine.arguments.contains("--measure-latency")
    static let output = FileManager.default.temporaryDirectory.appendingPathComponent("Bosun-latency.jsonl")
    private static let writer = DispatchQueue(label: "com.jcutplus.bosun.latency")
    let id = UUID().uuidString
    private let start: TimeInterval

    init(callbackAt: TimeInterval) {
        start = callbackAt
        mark("recognition_callback", at: callbackAt)
    }

    func mark(_ stage: String, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard Self.enabled else { return }
        let row: [String: Any] = ["id": id, "stage": stage, "elapsed_ms": (time - start) * 1000,
                                  "uptime": time, "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "test"]
        Self.writer.async {
            guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
            data.append(10)
            if let handle = try? FileHandle(forWritingTo: Self.output) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else { try? data.write(to: Self.output) }
        }
    }
}

// Segment timestamps refer to the submitted audio stream. This is an estimate,
// not an independently measured acoustic endpoint (buffer/device delay remains).
final class LatencyAudioTimeline {
    private let lock = NSLock()
    private var first: TimeInterval?
    var start: TimeInterval? { lock.lock(); defer { lock.unlock() }; return first }
    func observe(duration: TimeInterval) {
        guard LatencyTrace.enabled else { return }
        lock.lock(); defer { lock.unlock() }
        if first == nil { first = ProcessInfo.processInfo.systemUptime - duration }
    }
}
