import AppKit

/// The only permanent chrome: a glass pill in the top-right corner.
///
/// It sits as a single small circle until the pointer comes near, then springs
/// open into three buttons. Each opens a compact palette rather than adding more
/// controls to the bar itself, which keeps the resting state to one dot.
///
/// Everything it controls lives in `ThemeManager`, so the choices are app-wide
/// and persist across launches rather than belonging to one document.
final class DisplayOptionsBar: NSView {

    /// Pointer distance, in points, at which the bar opens. It closes a little
    /// further out so it does not flicker on the boundary.
    static let openDistance: CGFloat = 100
    static let closeDistance: CGFloat = 150

    private let collapsedWidth: CGFloat = 34
    private let barHeight: CGFloat = 34

    private var widthConstraint: NSLayoutConstraint!
    private let clip = NSView()
    private let icon = NSImageView()
    private let buttons = NSStackView()
    private let popover = NSPopover()

    private(set) var isExpanded = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerRadius = barHeight / 2
        clip.layer?.cornerCurve = .continuous
        clip.translatesAutoresizingMaskIntoConstraints = false

        // "Aa" is the established macOS glyph for type and appearance options.
        icon.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Display options")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        buildButtons()
        clip.addSubview(buttons)
        clip.addSubview(icon)

        popover.behavior = .transient

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

            // Pinned to the trailing edge so the pill grows leftwards out from
            // under the resting dot.
            buttons.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -7),
            buttons.centerYAnchor.constraint(equalTo: clip.centerYAnchor),
        ])

        buttons.alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Opening

    /// Hovering opens the bar too. Proximity gives it the feel of reaching for
    /// something, but a tracking area is what guarantees it opens at all.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        setExpanded(true)
    }

    /// Clicking the resting dot opens it. Without this the dot is inert whenever
    /// the pointer arrives without a tracked move, which made the whole control
    /// look broken.
    override func mouseDown(with event: NSEvent) {
        if !isExpanded {
            setExpanded(true)
            return
        }
        super.mouseDown(with: event)
    }

    private func buildButtons() {
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 2
        buttons.translatesAutoresizingMaskIntoConstraints = false

        for section in OptionsPalette.Section.allCases {
            buttons.addArrangedSubview(button(for: section))
        }
    }

    private func button(for section: OptionsPalette.Section) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.title = ""
        button.toolTip = section.title
        button.tag = section.rawValue
        button.target = self
        button.action = #selector(openPalette(_:))
        button.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }

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

    // MARK: - Expansion

    /// Called with the pointer position in this view's superview coordinates.
    func updateProximity(to point: NSPoint) {
        guard !popover.isShown else { return }
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

        let target = expanded ? buttons.fittingSize.width + 14 : collapsedWidth

        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.38 : 0.24
            // A curve that overshoots past 1 gives the pill a little bounce as
            // it opens, and a plain ease-in as it closes.
            context.timingFunction = expanded
                ? CAMediaTimingFunction(controlPoints: 0.3, 1.6, 0.55, 1)
                : CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true

            widthConstraint.animator().constant = target
            buttons.animator().alphaValue = expanded ? 1 : 0
            icon.animator().alphaValue = expanded ? 0 : 1
            superview?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Palettes

    var isOpen: Bool { popover.isShown }

    @objc private func openPalette(_ sender: NSButton) {
        guard let section = OptionsPalette.Section(rawValue: sender.tag) else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.contentViewController = OptionsPalette(section: section)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    /// Opens the bar and its first palette, for the keyboard shortcut.
    func present() {
        setExpanded(true)
        guard let first = buttons.arrangedSubviews.first as? NSButton else { return }
        openPalette(first)
    }

    func close() {
        popover.performClose(nil)
        setExpanded(false)
    }
}

/// One compact palette of settings, shown from the bar.
final class OptionsPalette: NSViewController {

    enum Section: Int, CaseIterable {
        case theme
        case typography
        case reading

        var title: String {
            switch self {
            case .theme: return "Theme"
            case .typography: return "Typography"
            case .reading: return "Reading"
            }
        }

        var symbol: String {
            switch self {
            case .theme: return "paintpalette"
            case .typography: return "textformat.size"
            case .reading: return "eyeglasses"
            }
        }
    }

    private let section: Section
    private var swatches: [PaletteSwatchButton] = []
    private let followSystem = NSButton(checkboxWithTitle: "Match system", target: nil, action: nil)
    private let typeface = NSPopUpButton()
    private let textSize = NSPopUpButton()
    private let measure = NSPopUpButton()
    private let focusToggle = NSButton(checkboxWithTitle: "Focus mode", target: nil, action: nil)
    private let typewriterToggle = NSButton(checkboxWithTitle: "Typewriter scrolling", target: nil, action: nil)
    private let markersToggle = NSButton(checkboxWithTitle: "Always show markers", target: nil, action: nil)

    init(section: Section) {
        self.section = section
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let container = NSView()
        let stack = NSStackView(views: content())
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        view = container
        sync()

        NotificationCenter.default.addObserver(
            self, selector: #selector(sync), name: .quillThemeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func content() -> [NSView] {
        switch section {
        case .theme:
            // Miniature pages in a grid, three to a row, the way a colour
            // palette reads.
            var rows: [NSView] = []
            for chunk in Palettes.all.chunked(into: 3) {
                let row = NSStackView(views: chunk.map { palette in
                    let swatch = PaletteSwatchButton(
                        palette: palette, target: self, action: #selector(selectPalette(_:)))
                    swatches.append(swatch)
                    return swatch
                })
                row.orientation = .horizontal
                row.spacing = 8
                row.alignment = .centerY
                rows.append(row)
            }
            followSystem.target = self
            followSystem.action = #selector(toggleFollowSystem)
            followSystem.font = .systemFont(ofSize: 11)
            return rows + [followSystem]

        case .typography:
            configure(typeface, titles: TypographyPreset.all.map(\.name), action: #selector(selectTypeface))
            configure(textSize, titles: TextSize.allCases.map(\.name), action: #selector(selectSize))
            configure(measure, titles: LineWidth.allCases.map(\.name), action: #selector(selectMeasure))
            for popup in [typeface, textSize, measure] {
                popup.widthAnchor.constraint(equalToConstant: 168).isActive = true
            }
            return [label("Typeface"), typeface, label("Size"), textSize, label("Width"), measure]

        case .reading:
            for toggle in [focusToggle, typewriterToggle, markersToggle] {
                toggle.target = self
                toggle.font = .systemFont(ofSize: 11)
            }
            focusToggle.action = #selector(toggleFocus)
            typewriterToggle.action = #selector(toggleTypewriter)
            markersToggle.action = #selector(toggleMarkers)
            return [focusToggle, typewriterToggle, markersToggle]
        }
    }

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

    @objc func sync() {
        let manager = ThemeManager.shared
        let active = manager.activePaletteID
        for swatch in swatches { swatch.isSelectedSwatch = swatch.palette.id == active }
        followSystem.state = manager.followsSystemAppearance ? .on : .off
        typeface.selectItem(at: TypographyPreset.all.firstIndex { $0.id == manager.presetID } ?? 0)
        textSize.selectItem(at: TextSize.allCases.firstIndex(of: manager.textSize) ?? 0)
        measure.selectItem(at: LineWidth.allCases.firstIndex(of: manager.lineWidth) ?? 0)
        focusToggle.state = manager.focusMode ? .on : .off
        typewriterToggle.state = manager.typewriterScrolling ? .on : .off
        markersToggle.state = manager.alwaysShowMarkers ? .on : .off
    }

    @objc private func selectPalette(_ sender: PaletteSwatchButton) {
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

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
