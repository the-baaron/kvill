import AppKit

/// The button that opens and closes the sidebar.
///
/// The action is AppKit's: `toggleSidebar(_:)` goes up the responder chain to
/// the window's `NSSplitViewController`, which knows how to collapse a sidebar
/// item and animate it. Nothing about that is written here.
///
/// The *look* is this app's, and matches the display options button on the other
/// side of the window: the same 34pt glass capsule, the same distance from the
/// top. It began as an `NSToolbarItem.Identifier.toggleSidebar` in a real
/// toolbar, which is the standard answer, but a toolbar sat the control at its
/// own height and drew its own capsule, so the two buttons at the two top
/// corners of the same window did not line up or match.
final class SidebarToggleButton: NSView {

    static let size: CGFloat = 34
    private let button = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Without this the autoresizing mask makes its own constraints, they
        // conflict with the ones below, and AppKit resolves that by breaking
        // somebody else's: the editor collapsed to 16pt.
        translatesAutoresizingMaskIntoConstraints = false

        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: "sidebar.leading",
            accessibilityDescription: "Show or hide the sidebar")
        button.image?.isTemplate = true
        button.contentTintColor = ThemeManager.shared.theme.colors.textSecondary
        button.toolTip = "Show or hide the sidebar"
        // Up the responder chain to the split view controller. Nil target is
        // what makes that happen.
        button.target = nil
        button.action = #selector(NSSplitViewController.toggleSidebar(_:))
        button.translatesAutoresizingMaskIntoConstraints = false

        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerRadius = Self.size / 2
        clip.layer?.cornerCurve = .continuous
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(button)

        let backdrop = makeBackdrop(content: clip)
        addSubview(backdrop)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.centerXAnchor.constraint(equalTo: clip.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: clip.centerYAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .kvillThemeChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        button.contentTintColor = ThemeManager.shared.theme.colors.textSecondary
    }

    /// The same glass the display options button sits on, so the two corners of
    /// the window match.
    private func makeBackdrop(content: NSView) -> NSView {
        let backdrop: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.size / 2
            glass.style = .regular
            glass.contentView = content
            backdrop = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Self.size / 2
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                content.topAnchor.constraint(equalTo: effect.topAnchor),
                content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            backdrop = effect
        }
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        return backdrop
    }
}
