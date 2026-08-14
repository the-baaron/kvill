import AppKit

/// The floating settings panel: colour theme, typography, size, measure and the
/// three reading toggles. Chrome, not document, so it uses system label colours
/// and lets the glass pick up the surrounding appearance.
final class ThemePanelView: NSView {

    private var swatches: [PaletteSwatchButton] = []
    private let followSystem = NSButton(checkboxWithTitle: "Follow system", target: nil, action: nil)
    private let presets = NSSegmentedControl()
    private let sizes = NSSegmentedControl()
    private let widths = NSSegmentedControl()
    private let focusToggle = NSButton(checkboxWithTitle: "Focus mode", target: nil, action: nil)
    private let typewriterToggle = NSButton(checkboxWithTitle: "Typewriter", target: nil, action: nil)
    private let markersToggle = NSButton(checkboxWithTitle: "Always show markers", target: nil, action: nil)
    private let presetBlurb = NSTextField(labelWithString: "")

    var onClose: (() -> Void)?

    init() {
        super.init(frame: .zero)
        build()
        sync()
        NotificationCenter.default.addObserver(
            self, selector: #selector(sync), name: .quillThemeChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Construction

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Appearance")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let close = NSButton()
        close.bezelStyle = .accessoryBarAction
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        close.target = self
        close.action = #selector(closePanel)
        close.setContentHuggingPriority(.required, for: .horizontal)

        followSystem.target = self
        followSystem.action = #selector(toggleFollowSystem)
        followSystem.font = .systemFont(ofSize: 11)

        let header = NSStackView(views: [title, NSView(), followSystem, close])
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY

        for palette in Palettes.all {
            let swatch = PaletteSwatchButton(palette: palette, target: self, action: #selector(selectPalette(_:)))
            swatches.append(swatch)
        }
        let swatchRow = NSStackView(views: swatches)
        swatchRow.orientation = .horizontal
        swatchRow.spacing = 6
        swatchRow.distribution = .fillEqually

        presets.segmentCount = TypographyPreset.all.count
        for (index, preset) in TypographyPreset.all.enumerated() {
            presets.setLabel(preset.name, forSegment: index)
            presets.setWidth(0, forSegment: index)
        }
        presets.segmentDistribution = .fillEqually
        presets.trackingMode = .selectOne
        presets.target = self
        presets.action = #selector(selectPreset)
        presets.font = .systemFont(ofSize: 11)

        presetBlurb.font = .systemFont(ofSize: 10.5)
        presetBlurb.textColor = .secondaryLabelColor
        presetBlurb.lineBreakMode = .byTruncatingTail
        presetBlurb.maximumNumberOfLines = 1

        sizes.segmentCount = TextSize.allCases.count
        for (index, size) in TextSize.allCases.enumerated() {
            sizes.setLabel(size.name, forSegment: index)
            sizes.setWidth(0, forSegment: index)
        }
        sizes.segmentDistribution = .fillEqually
        sizes.trackingMode = .selectOne
        sizes.target = self
        sizes.action = #selector(selectSize)
        sizes.font = .systemFont(ofSize: 11)

        widths.segmentCount = LineWidth.allCases.count
        for (index, width) in LineWidth.allCases.enumerated() {
            widths.setLabel(width.name, forSegment: index)
            widths.setWidth(0, forSegment: index)
        }
        widths.segmentDistribution = .fillEqually
        widths.trackingMode = .selectOne
        widths.target = self
        widths.action = #selector(selectWidth)
        widths.font = .systemFont(ofSize: 11)

        for toggle in [focusToggle, typewriterToggle, markersToggle] {
            toggle.target = self
            toggle.font = .systemFont(ofSize: 11)
        }
        focusToggle.action = #selector(toggleFocus)
        typewriterToggle.action = #selector(toggleTypewriter)
        markersToggle.action = #selector(toggleMarkers)

        let toggles = NSStackView(views: [focusToggle, typewriterToggle, markersToggle])
        toggles.orientation = .horizontal
        toggles.spacing = 14
        toggles.alignment = .centerY

        let stack = NSStackView(views: [
            header,
            swatchRow,
            sectionLabel("Typography"),
            presets,
            presetBlurb,
            sectionLabel("Size"),
            sizes,
            sectionLabel("Measure"),
            widths,
            separator(),
            toggles,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(12, after: swatchRow)
        stack.setCustomSpacing(4, after: presets)
        stack.setCustomSpacing(12, after: presetBlurb)
        stack.setCustomSpacing(12, after: sizes)
        stack.setCustomSpacing(14, after: widths)

        let glass = GlassContainerView(content: stack, cornerRadius: 22, padding: 18)
        addSubview(glass)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 360),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            swatchRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presets.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presetBlurb.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sizes.widthAnchor.constraint(equalTo: stack.widthAnchor),
            widths.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 9.5, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return line
    }

    // MARK: - State

    @objc func sync() {
        let manager = ThemeManager.shared
        let active = manager.activePaletteID
        for swatch in swatches {
            swatch.isSelectedSwatch = swatch.palette.id == active
        }
        followSystem.state = manager.followsSystemAppearance ? .on : .off

        if let index = TypographyPreset.all.firstIndex(where: { $0.id == manager.presetID }) {
            presets.selectedSegment = index
            presetBlurb.stringValue = TypographyPreset.all[index].blurb
        }
        if let index = TextSize.allCases.firstIndex(of: manager.textSize) {
            sizes.selectedSegment = index
        }
        if let index = LineWidth.allCases.firstIndex(of: manager.lineWidth) {
            widths.selectedSegment = index
        }
        focusToggle.state = manager.focusMode ? .on : .off
        typewriterToggle.state = manager.typewriterScrolling ? .on : .off
        markersToggle.state = manager.alwaysShowMarkers ? .on : .off
    }

    // MARK: - Actions

    @objc private func selectPalette(_ sender: PaletteSwatchButton) {
        ThemeManager.shared.selectPalette(id: sender.palette.id)
        sync()
    }

    @objc private func toggleFollowSystem() {
        ThemeManager.shared.followsSystemAppearance = followSystem.state == .on
        sync()
    }

    @objc private func selectPreset() {
        let index = presets.selectedSegment
        guard index >= 0, index < TypographyPreset.all.count else { return }
        ThemeManager.shared.presetID = TypographyPreset.all[index].id
        presetBlurb.stringValue = TypographyPreset.all[index].blurb
    }

    @objc private func selectSize() {
        let index = sizes.selectedSegment
        guard index >= 0, index < TextSize.allCases.count else { return }
        ThemeManager.shared.textSize = TextSize.allCases[index]
    }

    @objc private func selectWidth() {
        let index = widths.selectedSegment
        guard index >= 0, index < LineWidth.allCases.count else { return }
        ThemeManager.shared.lineWidth = LineWidth.allCases[index]
    }

    @objc private func toggleFocus() {
        ThemeManager.shared.focusMode = focusToggle.state == .on
    }

    @objc private func toggleTypewriter() {
        ThemeManager.shared.typewriterScrolling = typewriterToggle.state == .on
    }

    @objc private func toggleMarkers() {
        ThemeManager.shared.alwaysShowMarkers = markersToggle.state == .on
    }

    @objc private func closePanel() {
        onClose?()
    }
}
