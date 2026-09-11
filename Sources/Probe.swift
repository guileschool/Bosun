import Foundation
import AVFoundation
import Speech

// Headless, read-only diagnostic. Does not request permissions or control UI.
func runProbe() -> Int32 {
    let mic = AVCaptureDevice.authorizationStatus(for: .audio)
    let speech = SFSpeechRecognizer.authorizationStatus()
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    print("microphone_authorization=\(mic.rawValue) speech_authorization=\(speech.rawValue) (3=authorized)")
    print("recognizer_available=\(recognizer?.isAvailable == true) on_device=\(recognizer?.supportsOnDeviceRecognition == true)")
    guard mic == .authorized, speech == .authorized else { return 2 }
    guard let recognizer = recognizer, recognizer.supportsOnDeviceRecognition else { return 3 }
    let engine = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.contextualStrings = ["Record", "Cancel", "Submit"]
    request.taskHint = .confirmation
    let lock = NSLock()
    var buffers = 0
    var peak: Float = 0
    var results = 0
    var commands = Set<String>()
    var failures = [String]()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    print("sample_rate=\(format.sampleRate) channels=\(format.channelCount)")
    guard format.sampleRate > 0, format.channelCount > 0 else { return 4 }
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
        lock.lock()
        buffers += 1
        if let values = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(values[index])) }
        }
        lock.unlock()
    }
    let task = recognizer.recognitionTask(with: request) { result, error in
        lock.lock()
        defer { lock.unlock() }
        if let result = result {
            results += 1
            for segment in result.bestTranscription.segments {
                let word = segment.substring.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if ["record", "cancel", "submit"].contains(word) { commands.insert(word) }
            }
        }
        if let error = error as NSError? { failures.append("\(error.domain):\(error.code)") }
    }
    defer { engine.stop(); input.removeTap(onBus: 0); request.endAudio(); task.cancel() }
    do { engine.prepare(); try engine.start() }
    catch { print("engine_start_error=\(error)"); return 5 }
    RunLoop.current.run(until: Date().addingTimeInterval(8))
    lock.lock()
    let count = buffers
    print("buffers=\(buffers) peak=\(peak) recognition_callbacks=\(results) command_tokens=\(commands.sorted()) errors=\(failures)")
    lock.unlock()
    return count > 0 ? 0 : 6
}
