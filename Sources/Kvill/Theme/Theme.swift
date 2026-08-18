import AppKit

/// A fully resolved look: colours, typography preset, and every font and
/// measurement derived from them. Rebuilt only when the user changes something,
/// so styling a keystroke never touches font resolution.
final class Theme {
    let colors: ColorTheme
    let preset: TypographyPreset
    let size: TextSize
    let width: LineWidth
    let metrics: Metrics

    let body: NSFont
    let bodyBold: NSFont
    let bodyItalic: NSFont
    let bodyBoldItalic: NSFont
    let mono: NSFont
    let monoSmall: NSFont
    /// Table header rows. Semibold keeps the same advance width in a monospace
    /// face, so the columns stay aligned.
    let monoSmallBold: NSFont
    let marker: NSFont
    let markerBold: NSFont
    /// Used for the drawn callout title ("Note", "Warning", …).
    let calloutTitle: NSFont

    private let headingFonts: [NSFont]

    init(colors: ColorTheme, preset: TypographyPreset, size: TextSize, width: LineWidth) {
        self.colors = colors
        self.preset = preset
        self.size = size
        self.width = width
        self.metrics = Metrics(preset: preset, size: size, width: width)

        let base = metrics.base
        self.body = FontBuilder.font(preset.bodyFamily, size: base, weight: preset.bodyWeight)
        self.bodyBold = FontBuilder.font(preset.bodyFamily, size: base, weight: .bold)
        self.bodyItalic = FontBuilder.font(preset.bodyFamily, size: base, weight: preset.bodyWeight, italic: true)
        self.bodyBoldItalic = FontBuilder.font(preset.bodyFamily, size: base, weight: .bold, italic: true)
        self.mono = FontBuilder.font(.mono, size: base * 0.92)
        self.monoSmall = FontBuilder.font(.mono, size: base * 0.86)
        self.monoSmallBold = FontBuilder.font(.mono, size: base * 0.86, weight: .semibold)
        self.marker = FontBuilder.font(.mono, size: metrics.markerSize)
        self.markerBold = FontBuilder.font(.mono, size: metrics.markerSize, weight: .semibold)
        self.calloutTitle = FontBuilder.font(preset.bodyFamily, size: base * 0.92, weight: .bold)

        self.headingFonts = preset.headingScale.map { scale in
            FontBuilder.font(preset.headingFamily, size: base * scale, weight: preset.headingWeight)
        }
    }

    /// Heading font for level 1...6.
    func heading(level: Int) -> NSFont {
        let index = min(max(level, 1), headingFonts.count) - 1
        return headingFonts[index]
    }

    func headingSize(level: Int) -> CGFloat {
        heading(level: level).pointSize
    }

    func callout(_ kind: CalloutKind?) -> CalloutColors {
        guard let kind else { return colors.genericCallout }
        return colors.callouts[kind] ?? colors.genericCallout
    }

    var identifier: String {
        "\(colors.id)|\(preset.id)|\(size.rawValue)|\(width.rawValue)"
    }
}

extension Notification.Name {
    static let kvillThemeChanged = Notification.Name("KvillThemeChanged")
    static let kvillPreferencesChanged = Notification.Name("KvillPreferencesChanged")
}

/// Owns the current theme and the small set of reading preferences, and persists
/// them. Every editor observes `kvillThemeChanged` and restyles in place.
final class ThemeManager {
    static let shared = ThemeManager()

    private enum Key {
        static let palette = "kvill.palette"
        static let preset = "kvill.typography"
        static let size = "kvill.textSize"
        static let width = "kvill.lineWidth"
        static let followSystem = "kvill.followSystemAppearance"
        static let lightPalette = "kvill.lightPalette"
        static let darkPalette = "kvill.darkPalette"
        static let focusMode = "kvill.focusMode"
        static let typewriter = "kvill.typewriterScrolling"
        static let scrollPastEnd = "kvill.scrollPastEnd"
        static let showMarkers = "kvill.showMarkers"
        static let autosave = "kvill.autosave"
    }

    private let defaults = UserDefaults.standard

    private(set) var theme: Theme

    /// When true the palette follows the system light/dark setting, choosing
    /// between the user's preferred light palette and preferred dark palette.
    var followsSystemAppearance: Bool {
        didSet {
            defaults.set(followsSystemAppearance, forKey: Key.followSystem)
            rebuild()
        }
    }

    var lightPaletteID: String {
        didSet {
            defaults.set(lightPaletteID, forKey: Key.lightPalette)
            rebuild()
        }
    }

    var darkPaletteID: String {
        didSet {
            defaults.set(darkPaletteID, forKey: Key.darkPalette)
            rebuild()
        }
    }

    var presetID: String {
        didSet {
            defaults.set(presetID, forKey: Key.preset)
            rebuild()
        }
    }

    var textSize: TextSize {
        didSet {
            defaults.set(textSize.rawValue, forKey: Key.size)
            rebuild()
        }
    }

    var lineWidth: LineWidth {
        didSet {
            defaults.set(lineWidth.rawValue, forKey: Key.width)
            rebuild()
        }
    }

    /// Dims every paragraph except the one being edited.
    var focusMode: Bool {
        didSet {
            defaults.set(focusMode, forKey: Key.focusMode)
            NotificationCenter.default.post(name: .kvillPreferencesChanged, object: nil)
        }
    }

    /// Keeps the caret vertically centred while typing.
    var typewriterScrolling: Bool {
        didSet {
            defaults.set(typewriterScrolling, forKey: Key.typewriter)
            NotificationCenter.default.post(name: .kvillPreferencesChanged, object: nil)
        }
    }

    /// Keeps syntax markers dimly visible everywhere. Off, the default, reveals
    /// them only in the element the caret is in.
    /// Whether the document can be scrolled beyond its last line.
    var scrollPastEnd: Bool {
        didSet {
            defaults.set(scrollPastEnd, forKey: Key.scrollPastEnd)
            NotificationCenter.default.post(name: .kvillPreferencesChanged, object: nil)
        }
    }

    var alwaysShowMarkers: Bool {
        didSet {
            defaults.set(alwaysShowMarkers, forKey: Key.showMarkers)
            NotificationCenter.default.post(name: .kvillPreferencesChanged, object: nil)
        }
    }

    /// Whether a document writes itself as you type.
    ///
    /// On, and it stays on unless someone deliberately turns it off. Off makes
    /// Kvill an ordinary save-with-Cmd-S editor: closing an edited window asks
    /// what to do with it, which is AppKit's own sheet and not something written
    /// here.
    var autosaves: Bool {
        didSet {
            guard autosaves != oldValue else { return }
            defaults.set(autosaves, forKey: Key.autosave)
            NotificationCenter.default.post(name: .kvillPreferencesChanged, object: nil)
        }
    }

    /// Hides every piece of floating chrome. Deliberately not persisted: a
    /// launch should never start with the interface missing and no clue why.
    var chromeHidden = false {
        didSet {
            guard chromeHidden != oldValue else { return }
            NotificationCenter.default.post(name: .kvillPreferencesChanged, object: nil)
        }
    }

    private var appearanceObserver: NSKeyValueObservation?

    private init() {
        defaults.register(defaults: [
            Key.lightPalette: Palettes.paper.id,
            Key.darkPalette: Palettes.ink.id,
            Key.palette: Palettes.paper.id,
            Key.preset: TypographyPreset.editorial.id,
            Key.size: TextSize.medium.rawValue,
            Key.width: LineWidth.normal.rawValue,
            Key.followSystem: true,
            Key.focusMode: false,
            Key.typewriter: false,
            Key.showMarkers: false,
        ])

        followsSystemAppearance = defaults.bool(forKey: Key.followSystem)
        lightPaletteID = defaults.string(forKey: Key.lightPalette) ?? Palettes.paper.id
        darkPaletteID = defaults.string(forKey: Key.darkPalette) ?? Palettes.ink.id
        presetID = defaults.string(forKey: Key.preset) ?? TypographyPreset.editorial.id
        textSize = TextSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .medium
        lineWidth = LineWidth(rawValue: defaults.string(forKey: Key.width) ?? "") ?? .normal
        focusMode = defaults.bool(forKey: Key.focusMode)
        typewriterScrolling = defaults.bool(forKey: Key.typewriter)
        alwaysShowMarkers = defaults.bool(forKey: Key.showMarkers)
        // On unless it has been turned off: a document you cannot scroll to the
        // end of is the odd case, not the default.
        scrollPastEnd = defaults.object(forKey: Key.scrollPastEnd) as? Bool ?? true
        // The same shape, and for the same reason: an editor that does not save
        // your work is the odd case, so absent an answer the answer is yes.
        autosaves = defaults.object(forKey: Key.autosave) as? Bool ?? true

        theme = ThemeManager.build(
            paletteID: defaults.string(forKey: Key.palette) ?? Palettes.paper.id,
            presetID: presetID,
            size: textSize,
            width: lineWidth
        )

        rebuild()

        appearanceObserver = NSApp?.observe(\.effectiveAppearance) { [weak self] _, _ in
            guard let self, self.followsSystemAppearance else { return }
            self.rebuild()
        }
    }

    /// The palette currently in effect, accounting for the follow-system setting.
    var activePaletteID: String {
        guard followsSystemAppearance else {
            return defaults.string(forKey: Key.palette) ?? Palettes.paper.id
        }
        return systemIsDark ? darkPaletteID : lightPaletteID
    }

    private var systemIsDark: Bool {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Every display setting, so a headless render can put them back.
    ///
    /// A render is a read. `--render --theme nord` used to leave the user's own
    /// copy of Kvill set to Nord, which meant taking screenshots changed the
    /// app, silently and permanently.
    var settingsSnapshot: [String: Any?] {
        let keys = [
            Key.palette, Key.preset, Key.size, Key.width, Key.followSystem,
            Key.lightPalette, Key.darkPalette,
        ]
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
    }

    func restore(_ snapshot: [String: Any?]) {
        for (key, value) in snapshot {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        // The stored properties have to come back too. Putting only the defaults
        // back left the manager still holding the render's theme, so the next
        // rebuild in the same process would have written it out again.
        followsSystemAppearance = defaults.bool(forKey: Key.followSystem)
        lightPaletteID = defaults.string(forKey: Key.lightPalette) ?? Palettes.paper.id
        darkPaletteID = defaults.string(forKey: Key.darkPalette) ?? Palettes.ink.id
        presetID = defaults.string(forKey: Key.preset) ?? TypographyPreset.editorial.id
        textSize = TextSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .medium
        lineWidth = LineWidth(rawValue: defaults.string(forKey: Key.width) ?? "") ?? .normal
        rebuild()
    }

    /// Picks a palette explicitly. Doing so turns off following the system, since
    /// the two settings would otherwise fight each other on the next appearance change.
    func selectPalette(id: String) {
        defaults.set(id, forKey: Key.palette)
        if let selected = Palettes.theme(id: id) {
            if selected.isDark {
                darkPaletteID = id
            } else {
                lightPaletteID = id
            }
        }
        if followsSystemAppearance {
            followsSystemAppearance = false  // triggers rebuild
        } else {
            rebuild()
        }
    }

    private static func build(paletteID: String, presetID: String, size: TextSize, width: LineWidth) -> Theme {
        Theme(
            colors: Palettes.theme(id: paletteID) ?? Palettes.paper,
            preset: TypographyPreset.preset(id: presetID) ?? TypographyPreset.editorial,
            size: size,
            width: width
        )
    }

    private func rebuild() {
        let next = ThemeManager.build(
            paletteID: activePaletteID,
            presetID: presetID,
            size: textSize,
            width: lineWidth
        )
        guard next.identifier != theme.identifier else { return }
        theme = next
        NotificationCenter.default.post(name: .kvillThemeChanged, object: nil)
    }

    // MARK: - Step helpers used by the View menu

    func stepTextSize(by delta: Int) {
        let all = TextSize.allCases
        guard let index = all.firstIndex(of: textSize) else { return }
        let next = min(max(index + delta, 0), all.count - 1)
        textSize = all[next]
    }

    func resetTextSize() { textSize = .medium }

    /// Cycles to the next palette in the list, wrapping around.
    func cyclePalette() {
        let all = Palettes.all
        let index = all.firstIndex { $0.id == activePaletteID } ?? 0
        selectPalette(id: all[(index + 1) % all.count].id)
    }

    /// Cycles to the next typography preset, wrapping around.
    func cyclePreset() {
        let all = TypographyPreset.all
        let index = all.firstIndex { $0.id == presetID } ?? 0
        presetID = all[(index + 1) % all.count].id
    }
}
