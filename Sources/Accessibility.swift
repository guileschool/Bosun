import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import Speech


enum AX {
    static func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    static func string(_ e: AXUIElement, _ name: String) -> String {
        guard let v = value(e, name) else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func bool(_ e: AXUIElement, _ name: String) -> Bool {
        (value(e, name) as? Bool) ?? false
    }

    static func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ e: AXUIElement, _ name: String) -> [AXUIElement] {
        (value(e, name) as? [AXUIElement]) ?? []
    }

    static func children(_ e: AXUIElement) -> [AXUIElement] { elements(e, kAXChildrenAttribute as String) }
    static func parent(_ e: AXUIElement) -> AXUIElement? { element(e, kAXParentAttribute as String) }
    static func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute as String) }
    static func description(_ e: AXUIElement) -> String { string(e, kAXDescriptionAttribute as String) }

    static func position(_ e: AXUIElement) -> CGPoint {
        guard let v = value(e, kAXPositionAttribute as String), CFGetTypeID(v) == AXValueGetTypeID() else { return .zero }
        var p = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &p)
        return p
    }

    // Iterative DFS. The ChatGPT window is ~470 elements, so this is a few milliseconds.
    static func descendants(_ root: AXUIElement, maxDepth: Int = 80) -> [AXUIElement] {
        var out: [AXUIElement] = []
        var stack: [(AXUIElement, Int)] = children(root).map { ($0, 1) }
        while let (e, d) = stack.popLast() {
            out.append(e)
            if d < maxDepth { stack += children(e).map { ($0, d + 1) } }
        }
        return out
    }

    @discardableResult
    static func press(_ e: AXUIElement) -> Bool {
        AXUIElementPerformAction(e, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func focus(_ e: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - Composer model

enum Slot { case left, mic, right }

struct Composer {
    let textArea: AXUIElement
    let buttons: [Slot: AXUIElement]

    func button(_ s: Slot) -> AXUIElement? { buttons[s] }
    func label(_ s: Slot) -> String { buttons[s].map { AX.description($0) } ?? "" }

    var text: String { AX.string(textArea, kAXValueAttribute as String) }
    var textAreaFocused: Bool { AX.bool(textArea, kAXFocusedAttribute as String) }

    var isRecording: Bool { ChatGPTControl.isMicStopLabel(label(.mic)) }
    var canSend: Bool { ChatGPTControl.isSendLabel(label(.right)) && AX.bool(buttons[.right]!, kAXEnabledAttribute as String) }
    var canCancel: Bool { ChatGPTControl.isCancelLabel(label(.left)) }

    var summary: String {
        "left='\(label(.left))' mic='\(label(.mic))' right='\(label(.right))' recording=\(isRecording) canSend=\(canSend) text='\(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(30))'"
    }
}

