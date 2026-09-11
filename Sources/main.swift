import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import Speech


if CommandLine.arguments.contains("--probe") { exit(runProbe()) }

// Print what the finder sees without touching anything: Bosun --dump
if CommandLine.arguments.contains("--dump") {
    print("accessibility_trusted=\(ChatGPTControl.isAccessibilityTrusted(prompt: false))")
    do {
        let c = try ChatGPTControl.findComposer()
        print("composer: \(c.summary)")
        exit(0)
    } catch {
        print("composer=fail \(error)")
        exit(1)
    }
}

// Command-line check without voice: Bosun --click record|stop|cancel|send|clear|enter|space|home|end|break|delete|undo [--spoken N]
if let index = CommandLine.arguments.firstIndex(of: "--click"), index + 1 < CommandLine.arguments.count {
    guard let command = VoiceCommand(rawValue: CommandLine.arguments[index + 1].lowercased()) else {
        print("usage: --click record|stop|cancel|send|clear|enter|space|home|end|break|delete|undo")
        exit(64)
    }
    print("accessibility_trusted=\(ChatGPTControl.isAccessibilityTrusted(prompt: false))")
    if let index = CommandLine.arguments.firstIndex(of: "--spoken"), index + 1 < CommandLine.arguments.count,
       let value = Int(CommandLine.arguments[index + 1]) {
        ChatGPTControl.spokenCommandCount = value
    }
    ChatGPTControl.stepReporter = { print($0); fflush(stdout) }
    do {
        try ChatGPTControl.run(command)
        print("click_\(command.rawValue)=ok")
        exit(0)
    } catch {
        print("click_\(command.rawValue)=fail \(error)")
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = BosunApp()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
