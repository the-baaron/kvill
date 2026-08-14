import AppKit

/// A small glass confirmation that appears, holds, and fades. Used for actions
/// that would otherwise give no sign they happened, like saving.
final class ToastView: NSView {

    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private var dismissWork: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY

        let glass = GlassContainerView(content: row, cornerRadius: 15, padding: 10)
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Chrome only: never take a click meant for the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ message: String, symbol: String, for duration: TimeInterval = 1.4) {
        label.stringValue = message
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: message)

        dismissWork?.cancel()
        isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isHidden = true
        })
    }
}
