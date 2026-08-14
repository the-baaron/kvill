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

    /// Built once. Making one per update showed up in a profile of typing.
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    func update(text: String) {
        let words = Self.wordCount(text)
        // 220 wpm is a common average for prose read on screen.
        let minutes = max(1, Int((Double(words) / 220.0).rounded(.up)))
        let formatted = Self.formatter.string(from: NSNumber(value: words)) ?? "\(words)"
        label.stringValue = words == 0
            ? "Empty"
            : "\(formatted) word\(words == 1 ? "" : "s") · \(minutes) min read"
    }

    /// One pass over the bytes, counting the starts of words.
    ///
    /// `split` allocates a substring for every word, which on a large file is
    /// hundreds of thousands of allocations to produce a single number.
    private static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for byte in text.utf8 {
            let space = byte == 32 || byte == 10 || byte == 9 || byte == 13
            if space {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
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
