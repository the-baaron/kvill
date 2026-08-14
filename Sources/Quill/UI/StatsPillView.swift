import AppKit

/// A quiet glass pill in the corner with word count and reading time. Sits at low
/// opacity so it stays out of the way, and comes up to full strength on hover.
final class StatsPillView: NSView {

    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor

        let glass = GlassContainerView(content: label, cornerRadius: 13, padding: 9)
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        alphaValue = 0.35
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(text: String) {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
        // 220 wpm is a common average for prose read on screen.
        let minutes = max(1, Int((Double(words) / 220.0).rounded(.up)))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: words)) ?? "\(words)"
        label.stringValue = words == 0
            ? "Empty"
            : "\(formatted) word\(words == 1 ? "" : "s") · \(minutes) min read"
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        animator().alphaValue = 1.0
    }

    override func mouseExited(with event: NSEvent) {
        animator().alphaValue = 0.35
    }
}
