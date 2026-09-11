import AppKit

/// A compact native menu heading. Operational details stay in diagnostics.
final class MenuHeaderView: NSView {
    private let state = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: L10n.text("음성으로 받아쓰기 제어"))
    private let indicator = NSImageView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 92))
        let icon = NSImageView(frame: NSRect(x: 18, y: 40, width: 36, height: 36))
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            icon.image = NSImage(contentsOfFile: path)
        }
        addSubview(icon)
        let title = NSTextField(labelWithString: "Bosun")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 64, y: 59, width: 196, height: 20)
        addSubview(title)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 64, y: 40, width: 200, height: 17)
        addSubview(subtitle)
        indicator.frame = NSRect(x: 20, y: 14, width: 12, height: 12)
        addSubview(indicator)
        state.font = .systemFont(ofSize: 12)
        state.lineBreakMode = .byTruncatingTail
        state.frame = NSRect(x: 40, y: 11, width: 224, height: 18)
        addSubview(state)
        update(active: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(active: Bool) {
        state.stringValue = L10n.text(active ? "음성 명령 대기 중" : "음성 감지 꺼짐")
        indicator.image = NSImage(systemSymbolName: active ? "waveform" : "pause.circle", accessibilityDescription: nil)
        indicator.contentTintColor = active ? .systemGreen : .secondaryLabelColor
    }

    func setPermissionNeeded(_ needed: Bool) {
        subtitle.stringValue = L10n.text(needed ? "권한 설정 필요" : "음성으로 받아쓰기 제어")
    }

    func showError(_ message: String) {
        state.stringValue = message
        state.toolTip = message
        indicator.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        indicator.contentTintColor = .systemOrange
    }
}
