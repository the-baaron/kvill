import AppKit

/// The only permanent piece of chrome: a small glass button in the top-right
/// corner that opens the display options.
///
/// Everything it controls lives in `ThemeManager`, so the choices are app-wide
/// and persist across launches rather than belonging to one document.
final class DisplayOptionsButton: NSView {

    private static let side: CGFloat = 34

    private let button = NSButton()
    private let popover = NSPopover()

    var isOpen: Bool { popover.isShown }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // "Aa" is the established macOS glyph for type and appearance options,
        // the same one Books and Safari Reader use.
        button.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Display options")
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.contentTintColor = .labelColor
        button.isBordered = false
        button.title = ""
        button.toolTip = "Display options"
        button.target = self
        button.action = #selector(toggle)
        button.translatesAutoresizingMaskIntoConstraints = false

        let backdrop = makeBackdrop(content: button)
        addSubview(backdrop)

        popover.behavior = .transient
        popover.contentViewController = DisplayOptionsController()

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func makeBackdrop(content: NSView) -> NSView {
        let backdrop: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.side / 2
            glass.style = .regular
            glass.contentView = content
            backdrop = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Self.side / 2
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

    @objc func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            (popover.contentViewController as? DisplayOptionsController)?.sync()
            popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        }
    }

    func close() {
        popover.performClose(nil)
    }
}

/// Contents of the display options popover: a row of theme swatches and three
/// dropdowns, rather than a wall of buttons.
final class DisplayOptionsController: NSViewController {

    private var dots: [PaletteDotButton] = []
    private let followSystem = NSButton(checkboxWithTitle: "Match system light and dark",
                                        target: nil, action: nil)
    private let typeface = NSPopUpButton()
    private let textSize = NSPopUpButton()
    private let measure = NSPopUpButton()
    private let focusToggle = NSButton(checkboxWithTitle: "Focus mode", target: nil, action: nil)
    private let typewriterToggle = NSButton(checkboxWithTitle: "Typewriter scrolling",
                                            target: nil, action: nil)
    private let markersToggle = NSButton(checkboxWithTitle: "Always show syntax markers",
                                         target: nil, action: nil)

    override func loadView() {
        let container = NSView()

        for palette in Palettes.all {
            let dot = PaletteDotButton(palette: palette, target: self, action: #selector(selectPalette(_:)))
            dots.append(dot)
        }
        let swatches = NSStackView(views: dots)
        swatches.orientation = .horizontal
        swatches.spacing = 7

        followSystem.target = self
        followSystem.action = #selector(toggleFollowSystem)
        followSystem.font = .systemFont(ofSize: 11)

        configure(typeface, titles: TypographyPreset.all.map(\.name), action: #selector(selectTypeface))
        configure(textSize, titles: TextSize.allCases.map(\.name), action: #selector(selectSize))
        configure(measure, titles: LineWidth.allCases.map(\.name), action: #selector(selectMeasure))

        for toggle in [focusToggle, typewriterToggle, markersToggle] {
            toggle.target = self
            toggle.font = .systemFont(ofSize: 11)
        }
        focusToggle.action = #selector(toggleFocus)
        typewriterToggle.action = #selector(toggleTypewriter)
        markersToggle.action = #selector(toggleMarkers)

        let stack = NSStackView(views: [
            label("Theme"),
            swatches,
            followSystem,
            label("Typeface"),
            typeface,
            label("Text size"),
            textSize,
            label("Line width"),
            measure,
            separator(),
            focusToggle,
            typewriterToggle,
            markersToggle,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(10, after: swatches)
        stack.setCustomSpacing(14, after: followSystem)
        stack.setCustomSpacing(12, after: typeface)
        stack.setCustomSpacing(12, after: textSize)
        stack.setCustomSpacing(14, after: measure)
        stack.setCustomSpacing(12, after: separator())
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            stack.widthAnchor.constraint(equalToConstant: 212),
            typeface.widthAnchor.constraint(equalTo: stack.widthAnchor),
            textSize.widthAnchor.constraint(equalTo: stack.widthAnchor),
            measure.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        view = container
        sync()

        NotificationCenter.default.addObserver(
            self, selector: #selector(sync), name: .quillThemeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configure(_ popup: NSPopUpButton, titles: [String], action: Selector) {
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = action
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.translatesAutoresizingMaskIntoConstraints = false
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text.uppercased())
        field.font = .systemFont(ofSize: 9, weight: .semibold)
        field.textColor = .tertiaryLabelColor
        return field
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 212).isActive = true
        return line
    }

    // MARK: - State

    @objc func sync() {
        let manager = ThemeManager.shared
        let active = manager.activePaletteID
        for dot in dots { dot.isSelectedDot = dot.palette.id == active }

        followSystem.state = manager.followsSystemAppearance ? .on : .off
        typeface.selectItem(at: TypographyPreset.all.firstIndex { $0.id == manager.presetID } ?? 0)
        textSize.selectItem(at: TextSize.allCases.firstIndex(of: manager.textSize) ?? 0)
        measure.selectItem(at: LineWidth.allCases.firstIndex(of: manager.lineWidth) ?? 0)

        focusToggle.state = manager.focusMode ? .on : .off
        typewriterToggle.state = manager.typewriterScrolling ? .on : .off
        markersToggle.state = manager.alwaysShowMarkers ? .on : .off
    }

    // MARK: - Actions

    @objc private func selectPalette(_ sender: PaletteDotButton) {
        ThemeManager.shared.selectPalette(id: sender.palette.id)
        sync()
    }

    @objc private func toggleFollowSystem() {
        ThemeManager.shared.followsSystemAppearance = followSystem.state == .on
        sync()
    }

    @objc private func selectTypeface() {
        let index = typeface.indexOfSelectedItem
        guard index >= 0, index < TypographyPreset.all.count else { return }
        ThemeManager.shared.presetID = TypographyPreset.all[index].id
    }

    @objc private func selectSize() {
        let index = textSize.indexOfSelectedItem
        guard index >= 0, index < TextSize.allCases.count else { return }
        ThemeManager.shared.textSize = TextSize.allCases[index]
    }

    @objc private func selectMeasure() {
        let index = measure.indexOfSelectedItem
        guard index >= 0, index < LineWidth.allCases.count else { return }
        ThemeManager.shared.lineWidth = LineWidth.allCases[index]
    }

    @objc private func toggleFocus() { ThemeManager.shared.focusMode = focusToggle.state == .on }
    @objc private func toggleTypewriter() {
        ThemeManager.shared.typewriterScrolling = typewriterToggle.state == .on
    }
    @objc private func toggleMarkers() {
        ThemeManager.shared.alwaysShowMarkers = markersToggle.state == .on
    }
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
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(ovalIn: circle)
        palette.background.setFill()
        path.fill()

        palette.accent.setFill()
        NSBezierPath(ovalIn: circle.insetBy(dx: circle.width * 0.30, dy: circle.height * 0.30)).fill()

        if isSelectedDot {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            ring.stroke()
        } else {
            palette.text.withAlpha(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}
