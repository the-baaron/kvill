import AppKit

/// Wraps content in Liquid Glass on macOS 26, and falls back to a vibrancy
/// material on earlier systems so the app still looks intentional there.
final class GlassContainerView: NSView {

    private let padding: CGFloat
    private let radius: CGFloat

    init(content: NSView, cornerRadius: CGFloat = 20, padding: CGFloat = 16, tint: NSColor? = nil) {
        self.padding = padding
        self.radius = cornerRadius
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: body.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -padding),
        ])

        let backdrop: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            if let tint { glass.tintColor = tint }
            glass.contentView = body
            backdrop = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.addSubview(body)
            backdrop = effect
        }

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            body.topAnchor.constraint(equalTo: backdrop.topAnchor),
            body.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
