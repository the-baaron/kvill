import AppKit

/// A small circular glass button in the top-right corner that springs open into
/// a display-options toolbar when the pointer comes near it, and shrinks back
/// when the pointer leaves.
///
/// Everything it controls lives in `ThemeManager`, so the choices are app-wide
/// and persist across launches rather than belonging to one document.
final class DisplayOptionsBar: NSView {

    /// Pointer distance, in points, at which the bar opens. It closes again a
    /// little further out so it does not flicker on the boundary.
    static let openDistance: CGFloat = 100
    static let closeDistance: CGFloat = 140

    private let collapsedWidth: CGFloat = 38
    private let barHeight: CGFloat = 38

    private var widthConstraint: NSLayoutConstraint!
    private let clip = NSView()
    private let icon = NSImageView()
    private let controls = NSStackView()
    private var dots: [PaletteDotButton] = []
    private var focusButton: NSButton!
    private var typewriterButton: NSButton!
    private var markersButton: NSButton!

    private(set) var isExpanded = false

    /// Opens the full settings panel.
    var onShowFullPanel: (() -> Void)?

    // MARK: - Construction

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerRadius = barHeight / 2
        clip.layer?.cornerCurve = .continuous
        clip.translatesAutoresizingMaskIntoConstraints = false

        buildControls()

        icon.image = NSImage(
            systemSymbolName: "textformat", accessibilityDescription: "Display options")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        clip.addSubview(controls)
        clip.addSubview(icon)

        let backdrop = makeBackdrop(content: clip)
        addSubview(backdrop)

        widthConstraint = widthAnchor.constraint(equalToConstant: collapsedWidth)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalToConstant: barHeight),

            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

            icon.centerXAnchor.constraint(equalTo: clip.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: clip.centerYAnchor),

            // Pinned to the trailing edge so the controls stay put and the pill
            // grows leftwards out from under the button.
            controls.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -9),
            controls.centerYAnchor.constraint(equalTo: clip.centerYAnchor),
        ])

        controls.alphaValue = 0
        sync()

        NotificationCenter.default.addObserver(
            self, selector: #selector(sync), name: .quillThemeChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sync), name: .quillPreferencesChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func makeBackdrop(content: NSView) -> NSView {
        let backdrop: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = barHeight / 2
            glass.style = .regular
            glass.contentView = content
            backdrop = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = barHeight / 2
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            backdrop = effect
        }
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            content.topAnchor.constraint(equalTo: backdrop.topAnchor),
            content.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
        return backdrop
    }

    private func buildControls() {
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 3
        controls.translatesAutoresizingMaskIntoConstraints = false

        for palette in Palettes.all {
            let dot = PaletteDotButton(palette: palette, target: self, action: #selector(selectPalette(_:)))
            dots.append(dot)
            controls.addArrangedSubview(dot)
        }

        controls.addArrangedSubview(divider())
        controls.addArrangedSubview(
            iconButton("textformat.size.smaller", "Smaller text", #selector(decreaseSize)))
        controls.addArrangedSubview(
            iconButton("textformat.size.larger", "Larger text", #selector(increaseSize)))
        controls.addArrangedSubview(
            iconButton("character.cursor.ibeam", "Next typeface", #selector(cycleTypography)))

        controls.addArrangedSubview(divider())
        focusButton = iconButton("scope", "Focus mode", #selector(toggleFocus))
        typewriterButton = iconButton("text.aligncenter", "Typewriter scrolling", #selector(toggleTypewriter))
        markersButton = iconButton("number", "Always show syntax markers", #selector(toggleMarkers))
        controls.addArrangedSubview(focusButton)
        controls.addArrangedSubview(typewriterButton)
        controls.addArrangedSubview(markersButton)

        controls.addArrangedSubview(divider())
        controls.addArrangedSubview(
            iconButton("ellipsis", "All settings", #selector(showFullPanel)))
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.title = ""
        button.toolTip = label
        button.target = self
        button.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }

    private func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 14),
        ])
        return line
    }

    // MARK: - Expansion

    /// Called with the pointer position in this view's superview coordinates.
    func updateProximity(to point: NSPoint) {
        let distance = distanceFromFrame(to: point)
        if !isExpanded, distance <= Self.openDistance {
            setExpanded(true)
        } else if isExpanded, distance > Self.closeDistance {
            setExpanded(false)
        }
    }

    private func distanceFromFrame(to point: NSPoint) -> CGFloat {
        let box = frame
        let dx = max(box.minX - point.x, 0, point.x - box.maxX)
        let dy = max(box.minY - point.y, 0, point.y - box.maxY)
        return sqrt(dx * dx + dy * dy)
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if expanded { sync() }

        let target = expanded
            ? controls.fittingSize.width + 18
            : collapsedWidth

        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.42 : 0.26
            // A cubic curve with an overshoot past 1 gives the bubble a little
            // bounce as it opens, and a plain ease-in as it closes.
            context.timingFunction = expanded
                ? CAMediaTimingFunction(controlPoints: 0.32, 1.62, 0.55, 1)
                : CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true

            widthConstraint.animator().constant = target
            controls.animator().alphaValue = expanded ? 1 : 0
            icon.animator().alphaValue = expanded ? 0 : 1
            superview?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - State

    @objc func sync() {
        let manager = ThemeManager.shared
        let active = manager.activePaletteID
        for dot in dots { dot.isSelectedDot = dot.palette.id == active }

        focusButton?.contentTintColor = manager.focusMode ? .controlAccentColor : .secondaryLabelColor
        typewriterButton?.contentTintColor =
            manager.typewriterScrolling ? .controlAccentColor : .secondaryLabelColor
        markersButton?.contentTintColor =
            manager.alwaysShowMarkers ? .controlAccentColor : .secondaryLabelColor
    }

    // MARK: - Actions

    @objc private func selectPalette(_ sender: PaletteDotButton) {
        ThemeManager.shared.selectPalette(id: sender.palette.id)
    }

    @objc private func increaseSize() { ThemeManager.shared.stepTextSize(by: 1) }
    @objc private func decreaseSize() { ThemeManager.shared.stepTextSize(by: -1) }
    @objc private func cycleTypography() { ThemeManager.shared.cyclePreset() }
    @objc private func toggleFocus() { ThemeManager.shared.focusMode.toggle() }
    @objc private func toggleTypewriter() { ThemeManager.shared.typewriterScrolling.toggle() }
    @objc private func toggleMarkers() { ThemeManager.shared.alwaysShowMarkers.toggle() }
    @objc private func showFullPanel() { onShowFullPanel?() }
}

/// A palette shown as a filled circle: the theme's page colour with its accent
/// as a small inner dot, so the six read apart at a glance.
final class PaletteDotButton: NSButton {

    let palette: ColorTheme
    var isSelectedDot = false {
        didSet { needsDisplay = true }
    }

    init(palette: ColorTheme, target: AnyObject?, action: Selector) {
        self.palette = palette
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        toolTip = palette.name
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(ovalIn: circle)
        palette.background.setFill()
        path.fill()

        palette.accent.setFill()
        NSBezierPath(ovalIn: circle.insetBy(dx: circle.width * 0.31, dy: circle.height * 0.31)).fill()

        if isSelectedDot {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.8
            ring.stroke()
        } else {
            palette.text.withAlpha(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}
