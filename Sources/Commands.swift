import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import Speech


enum VoiceCommand: String, CaseIterable {
    case record, stop, cancel, clear, enter, space, home, end, delete, undo
    case submit = "send"
    case abort = "break"

    var label: String {
        switch self {
        case .record: return L10n.text("녹음 시작")
        case .stop:   return L10n.text("녹음 정지 (전사 유지)")
        case .cancel: return L10n.text("받아쓰기 취소 (전사 버림)")
        case .submit: return L10n.text("녹음 정지 → 명령어 삭제 → 제출")
        case .clear: return L10n.text("action.clear")
        case .enter: return L10n.text("action.enter")
        case .space: return L10n.text("action.space")
        case .home: return L10n.text("action.home")
        case .end: return L10n.text("action.end")
        case .delete: return L10n.text("action.delete")
        case .undo: return L10n.text("action.undo")
        case .abort: return L10n.text("action.abort")
        }
    }

    var menuTitle: String {
        switch self {
        case .record: return L10n.text("action.record")
        case .stop: return L10n.text("action.stop")
        case .cancel: return L10n.text("action.cancel")
        case .submit: return L10n.text("action.submit")
        case .clear: return L10n.text("action.clear")
        case .enter: return L10n.text("action.enter")
        case .space: return L10n.text("action.space")
        case .home: return L10n.text("action.home")
        case .end: return L10n.text("action.end")
        case .delete: return L10n.text("action.delete")
        case .undo: return L10n.text("action.undo")
        case .abort: return L10n.text("action.abort")
        }
    }

    var title: String { rawValue.capitalized }
}

enum CommandMode: String {
    case korean = "ko"   // bare command word
    case english = "en"  // "<command> please" required

    var label: String {
        switch self {
        case .korean:  return L10n.text("명령어 모드: 한국어 (단독 단어: record / stop / cancel / submit)")
        case .english: return L10n.text("명령어 모드: 영어 (복합어: record please / stop please / cancel please / submit please)")
        }
    }

    static var current: CommandMode {
        get { CommandMode(rawValue: UserDefaults.standard.string(forKey: "commandMode") ?? "ko") ?? .korean }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "commandMode") }
    }
}

enum CommandSuffix {
    static let canonical = "please"
    static let english: Set<String> = ["please", "pleas", "plees", "police", "plz"]
    static let korean: Set<String> = ["플리즈", "플리스", "프리즈", "플리", "플리즈."]

    static func matches(_ raw: String) -> Bool {
        let w = raw.lowercased().trimmingCharacters(in: ChatGPTControl.tokenPunctuation)
        return english.contains(w) || korean.contains(w)
    }

    // "서브밋플리즈" / "submitplease": split a merged suffix off the end of a token.
    static func splitMerged(_ raw: String) -> String? {
        let w = raw.lowercased().trimmingCharacters(in: ChatGPTControl.tokenPunctuation)
        for suffix in korean.union(["please"]) where w.count > suffix.count && w.hasSuffix(suffix) {
            return String(w.dropLast(suffix.count))
        }
        return nil
    }
}


// Recognition settling is separate from duplicate suppression.
enum CommandTiming {
    static func settling(_ command: VoiceCommand) -> TimeInterval { command == .submit ? 0.30 : 0.18 }
    static func cooldown(previous: VoiceCommand?, next: VoiceCommand) -> TimeInterval { previous == next ? 0.60 : 0.15 }
}

struct DeletionRestore {
    let before: String
    let after: String
    static func consume(_ saved: inout DeletionRestore?, current: String, sameInput: Bool) -> String? {
        defer { saved = nil }
        guard let value = saved, sameInput, current == value.after else { return nil }
        return value.before
    }
}
