import AppKit

extension NSColor {
    /// Builds a colour from a `#RRGGBB` string. Falls back to magenta so a typo is
    /// visible rather than silently rendering as black.
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            self.init(srgbRed: 1, green: 0, blue: 1, alpha: alpha)
            return
        }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    func withAlpha(_ a: CGFloat) -> NSColor { withAlphaComponent(a) }
}

/// The five GitHub alert types, plus a generic fallback for unrecognised labels.
enum CalloutKind: String, CaseIterable {
    case note = "NOTE"
    case tip = "TIP"
    case important = "IMPORTANT"
    case warning = "WARNING"
    case caution = "CAUTION"

    var title: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }

    /// SF Symbol drawn in the callout's left margin.
    var symbolName: String {
        switch self {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "exclamationmark.octagon.fill"
        }
    }
}

struct CalloutColors {
    let accent: NSColor
    let background: NSColor
}

struct ColorTheme {
    let id: String
    let name: String
    let isDark: Bool

    let background: NSColor
    let backgroundElevated: NSColor
    let text: NSColor
    let textSecondary: NSColor

    /// Colour of syntax markers resting in the gutter and inline.
    let marker: NSColor
    /// Marker colour on the line holding the caret.
    let markerActive: NSColor

    let accent: NSColor
    let heading: NSColor
    let link: NSColor

    let code: NSColor
    let codeBackground: NSColor
    let codeBorder: NSColor

    let quoteBar: NSColor
    let quoteText: NSColor

    let rule: NSColor
    let selection: NSColor
    let cursor: NSColor

    let tableBorder: NSColor
    let tableHeaderBackground: NSColor
    let tableStripe: NSColor

    let highlightBackground: NSColor
    let taskDone: NSColor

    let callouts: [CalloutKind: CalloutColors]
    let genericCallout: CalloutColors

    /// When true the page is painted semi-transparent over a window-level blur,
    /// so the desktop shows faintly through, the way a native macOS window does.
    var isTranslucent: Bool = false
    /// How strongly the palette's own colour is laid over the material. Only
    /// meaningful when translucent, and deliberately light: a heavy tint is just
    /// a flat colour with a blurred desktop wasted behind it.
    var pageAlpha: CGFloat = 1
    /// Material for the window-level blur behind a translucent page.
    ///
    /// `.sidebar` is the translucent semantic material. The obvious-sounding
    /// `.underWindowBackground` is for the area *under* a window, and
    /// `.windowBackground` and `.contentBackground` are both documented as
    /// opaque, which is why an earlier version of these palettes had no glass in
    /// them at all.
    var material: NSVisualEffectView.Material = .sidebar

    /// The page colour as it should actually be painted.
    var page: NSColor {
        isTranslucent ? background.withAlphaComponent(pageAlpha) : background
    }

    var appearance: NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

private func callouts(
    note: String, tip: String, important: String, warning: String, caution: String,
    tint: CGFloat
) -> [CalloutKind: CalloutColors] {
    [
        .note: CalloutColors(accent: NSColor(hex: note), background: NSColor(hex: note, alpha: tint)),
        .tip: CalloutColors(accent: NSColor(hex: tip), background: NSColor(hex: tip, alpha: tint)),
        .important: CalloutColors(accent: NSColor(hex: important), background: NSColor(hex: important, alpha: tint)),
        .warning: CalloutColors(accent: NSColor(hex: warning), background: NSColor(hex: warning, alpha: tint)),
        .caution: CalloutColors(accent: NSColor(hex: caution), background: NSColor(hex: caution, alpha: tint)),
    ]
}

enum Palettes {

    static let paper = ColorTheme(
        id: "paper",
        name: "Paper",
        isDark: false,
        background: NSColor(hex: "#FBFAF7"),
        backgroundElevated: NSColor(hex: "#FFFFFF"),
        text: NSColor(hex: "#26231F"),
        textSecondary: NSColor(hex: "#6B655E"),
        marker: NSColor(hex: "#C3BCB2"),
        markerActive: NSColor(hex: "#8B8279"),
        accent: NSColor(hex: "#A65D3A"),
        heading: NSColor(hex: "#191612"),
        link: NSColor(hex: "#2E6E9E"),
        code: NSColor(hex: "#A33A5E"),
        codeBackground: NSColor(hex: "#F2EFE9"),
        codeBorder: NSColor(hex: "#E5E0D6"),
        quoteBar: NSColor(hex: "#D9D2C6"),
        quoteText: NSColor(hex: "#56504A"),
        rule: NSColor(hex: "#E2DCD1"),
        selection: NSColor(hex: "#C9DCEA"),
        cursor: NSColor(hex: "#A65D3A"),
        tableBorder: NSColor(hex: "#E2DCD1"),
        tableHeaderBackground: NSColor(hex: "#F4F1EA"),
        tableStripe: NSColor(hex: "#F7F5F0"),
        highlightBackground: NSColor(hex: "#FBE9A7"),
        taskDone: NSColor(hex: "#8B8279"),
        callouts: callouts(
            note: "#3B7EA1", tip: "#3F8B54", important: "#7C5BB5",
            warning: "#B4801F", caution: "#C1483C", tint: 0.08),
        genericCallout: CalloutColors(
            accent: NSColor(hex: "#6B655E"), background: NSColor(hex: "#6B655E", alpha: 0.07))
    )

    static let ink = ColorTheme(
        id: "ink",
        name: "Ink",
        isDark: true,
        background: NSColor(hex: "#1A1B1E"),
        backgroundElevated: NSColor(hex: "#212327"),
        text: NSColor(hex: "#DBD7D1"),
        textSecondary: NSColor(hex: "#918B84"),
        marker: NSColor(hex: "#4E4C48"),
        markerActive: NSColor(hex: "#8A857D"),
        accent: NSColor(hex: "#D08A5D"),
        heading: NSColor(hex: "#F0ECE6"),
        link: NSColor(hex: "#7BB0D6"),
        code: NSColor(hex: "#E594AC"),
        codeBackground: NSColor(hex: "#212429"),
        codeBorder: NSColor(hex: "#2D3036"),
        quoteBar: NSColor(hex: "#3B3E43"),
        quoteText: NSColor(hex: "#A9A39B"),
        rule: NSColor(hex: "#2E3136"),
        selection: NSColor(hex: "#37414D"),
        cursor: NSColor(hex: "#D08A5D"),
        tableBorder: NSColor(hex: "#2E3136"),
        tableHeaderBackground: NSColor(hex: "#22252A"),
        tableStripe: NSColor(hex: "#1D1F23"),
        highlightBackground: NSColor(hex: "#6A5518"),
        taskDone: NSColor(hex: "#6E6862"),
        callouts: callouts(
            note: "#6FA8CC", tip: "#7FBF8F", important: "#B08FE0",
            warning: "#DFB663", caution: "#E28377", tint: 0.13),
        genericCallout: CalloutColors(
            accent: NSColor(hex: "#918B84"), background: NSColor(hex: "#918B84", alpha: 0.10))
    )

    static let sepia = ColorTheme(
        id: "sepia",
        name: "Sepia",
        isDark: false,
        background: NSColor(hex: "#F4ECD8"),
        backgroundElevated: NSColor(hex: "#FBF5E6"),
        text: NSColor(hex: "#3A2F21"),
        textSecondary: NSColor(hex: "#7A6A52"),
        marker: NSColor(hex: "#C6B694"),
        markerActive: NSColor(hex: "#98835F"),
        accent: NSColor(hex: "#9A5B2E"),
        heading: NSColor(hex: "#2B2216"),
        link: NSColor(hex: "#2F6A7A"),
        code: NSColor(hex: "#8E4A2F"),
        codeBackground: NSColor(hex: "#EBE1C7"),
        codeBorder: NSColor(hex: "#DCCFAF"),
        quoteBar: NSColor(hex: "#D2C39F"),
        quoteText: NSColor(hex: "#5E5140"),
        rule: NSColor(hex: "#DCCFAF"),
        selection: NSColor(hex: "#DFCB9E"),
        cursor: NSColor(hex: "#9A5B2E"),
        tableBorder: NSColor(hex: "#DCCFAF"),
        tableHeaderBackground: NSColor(hex: "#EDE3CB"),
        tableStripe: NSColor(hex: "#F1E8D2"),
        highlightBackground: NSColor(hex: "#EBD489"),
        taskDone: NSColor(hex: "#98835F"),
        callouts: callouts(
            note: "#2F6A7A", tip: "#4F7A3A", important: "#6E5398",
            warning: "#9A7017", caution: "#AE4433", tint: 0.10),
        genericCallout: CalloutColors(
            accent: NSColor(hex: "#7A6A52"), background: NSColor(hex: "#7A6A52", alpha: 0.09))
    )

    static let nord = ColorTheme(
        id: "nord",
        name: "Nord",
        isDark: true,
        background: NSColor(hex: "#2E3440"),
        backgroundElevated: NSColor(hex: "#3B4252"),
        text: NSColor(hex: "#D8DEE9"),
        textSecondary: NSColor(hex: "#8792A5"),
        marker: NSColor(hex: "#4C566A"),
        markerActive: NSColor(hex: "#7B879C"),
        accent: NSColor(hex: "#88C0D0"),
        heading: NSColor(hex: "#ECEFF4"),
        link: NSColor(hex: "#81A1C1"),
        code: NSColor(hex: "#D08770"),
        codeBackground: NSColor(hex: "#353C4A"),
        codeBorder: NSColor(hex: "#434C5E"),
        quoteBar: NSColor(hex: "#4C566A"),
        quoteText: NSColor(hex: "#A7B0C0"),
        rule: NSColor(hex: "#434C5E"),
        selection: NSColor(hex: "#434C5E"),
        cursor: NSColor(hex: "#88C0D0"),
        tableBorder: NSColor(hex: "#434C5E"),
        tableHeaderBackground: NSColor(hex: "#39404E"),
        tableStripe: NSColor(hex: "#323945"),
        highlightBackground: NSColor(hex: "#6B5A2E"),
        taskDone: NSColor(hex: "#6C7788"),
        callouts: callouts(
            note: "#88C0D0", tip: "#A3BE8C", important: "#B48EAD",
            warning: "#EBCB8B", caution: "#BF616A", tint: 0.14),
        genericCallout: CalloutColors(
            accent: NSColor(hex: "#8792A5"), background: NSColor(hex: "#8792A5", alpha: 0.10))
    )

    static let contrastLight = ColorTheme(
        id: "contrast-light",
        name: "High Contrast Light",
        isDark: false,
        background: NSColor(hex: "#FFFFFF"),
        backgroundElevated: NSColor(hex: "#FFFFFF"),
        text: NSColor(hex: "#000000"),
        textSecondary: NSColor(hex: "#333333"),
        marker: NSColor(hex: "#6E6E6E"),
        markerActive: NSColor(hex: "#000000"),
        accent: NSColor(hex: "#0B4FCB"),
        heading: NSColor(hex: "#000000"),
        link: NSColor(hex: "#0B4FCB"),
        code: NSColor(hex: "#8A0F3C"),
        codeBackground: NSColor(hex: "#F0F0F0"),
        codeBorder: NSColor(hex: "#000000"),
        quoteBar: NSColor(hex: "#000000"),
        quoteText: NSColor(hex: "#1A1A1A"),
        rule: NSColor(hex: "#000000"),
        selection: NSColor(hex: "#A8CBFF"),
        cursor: NSColor(hex: "#000000"),
        tableBorder: NSColor(hex: "#000000"),
        tableHeaderBackground: NSColor(hex: "#E8E8E8"),
        tableStripe: NSColor(hex: "#F6F6F6"),
        highlightBackground: NSColor(hex: "#FFE95C"),
        taskDone: NSColor(hex: "#4A4A4A"),
        callouts: callouts(
            note: "#0B4FCB", tip: "#0A6B2E", important: "#5B2D91",
            warning: "#7A4E00", caution: "#A81414", tint: 0.12),
        genericCallout: CalloutColors(
            accent: NSColor(hex: "#333333"), background: NSColor(hex: "#333333", alpha: 0.10))
    )

    static let contrastDark = ColorTheme(
        id: "contrast-dark",
        name: "High Contrast Dark",
        isDark: true,
        background: NSColor(hex: "#000000"),
        backgroundElevated: NSColor(hex: "#0D0D0D"),
        text: NSColor(hex: "#FFFFFF"),
        textSecondary: NSColor(hex: "#D2D2D2"),
        marker: NSColor(hex: "#8E8E8E"),
        markerActive: NSColor(hex: "#FFFFFF"),
        accent: NSColor(hex: "#7FB7FF"),
        heading: NSColor(hex: "#FFFFFF"),
        link: NSColor(hex: "#7FB7FF"),
        code: NSColor(hex: "#FF9EC4"),
        codeBackground: NSColor(hex: "#141414"),
        codeBorder: NSColor(hex: "#FFFFFF"),
        quoteBar: NSColor(hex: "#FFFFFF"),
        quoteText: NSColor(hex: "#E8E8E8"),
        rule: NSColor(hex: "#FFFFFF"),
        selection: NSColor(hex: "#0B4FCB"),
        cursor: NSColor(hex: "#FFFFFF"),
        tableBorder: NSColor(hex: "#FFFFFF"),
        tableHeaderBackground: NSColor(hex: "#1C1C1C"),
        tableStripe: NSColor(hex: "#101010"),
        highlightBackground: NSColor(hex: "#7A6200"),
        taskDone: NSColor(hex: "#B0B0B0"),
        callouts: callouts(
            note: "#7FB7FF", tip: "#7CE0A0", important: "#D6A8FF",
            warning: "#FFD466", caution: "#FF8C8C", tint: 0.18),
        genericCallout: CalloutColors(
            accent: NSColor(hex: "#D2D2D2"), background: NSColor(hex: "#D2D2D2", alpha: 0.14))
    )

    /// Light glass: a near-opaque page over a window blur. The closest of the
    /// set to a stock macOS document window.
    static let frost = ColorTheme(
        id: "frost",
        name: "Frost",
        isDark: false,
        background: NSColor(hex: "#F6F6F8"),
        backgroundElevated: NSColor(hex: "#FFFFFF"),
        text: NSColor(hex: "#1D1D1F"),
        textSecondary: NSColor(hex: "#6E6E73"),
        marker: NSColor(hex: "#C2C2C8"),
        markerActive: NSColor(hex: "#86868B"),
        accent: NSColor(hex: "#0A6CFF"),
        heading: NSColor(hex: "#111113"),
        link: NSColor(hex: "#0A6CFF"),
        code: NSColor(hex: "#B02A5B"),
        codeBackground: NSColor(hex: "#ECECF1"),
        codeBorder: NSColor(hex: "#DEDEE5"),
        quoteBar: NSColor(hex: "#D2D2D9"),
        quoteText: NSColor(hex: "#4A4A4F"),
        rule: NSColor(hex: "#DEDEE5"),
        selection: NSColor(hex: "#B7D3FF"),
        cursor: NSColor(hex: "#0A6CFF"),
        tableBorder: NSColor(hex: "#DEDEE5"),
        tableHeaderBackground: NSColor(hex: "#EDEDF2"),
        tableStripe: NSColor(hex: "#F2F2F6"),
        highlightBackground: NSColor(hex: "#FFE79A"),
        taskDone: NSColor(hex: "#86868B"),
        callouts: callouts(
            note: "#0A6CFF", tip: "#28874A", important: "#7A4FD0",
            warning: "#A97400", caution: "#D0342C", tint: 0.09),
        genericCallout: CalloutColors(
            accent: NSColor(hex: "#6E6E73"), background: NSColor(hex: "#6E6E73", alpha: 0.08)),
        isTranslucent: true,
        pageAlpha: 0.16,
        material: .sidebar
    )

    /// Dark glass, the same idea after dark.
    static let onyx = ColorTheme(
        id: "onyx",
        name: "Onyx",
        isDark: true,
        background: NSColor(hex: "#1C1C1E"),
        backgroundElevated: NSColor(hex: "#242427"),
        text: NSColor(hex: "#E6E6EB"),
        textSecondary: NSColor(hex: "#98989F"),
        marker: NSColor(hex: "#4B4B52"),
        markerActive: NSColor(hex: "#8E8E96"),
        accent: NSColor(hex: "#0A84FF"),
        heading: NSColor(hex: "#F5F5F7"),
        link: NSColor(hex: "#64D2FF"),
        code: NSColor(hex: "#FF8AB3"),
        codeBackground: NSColor(hex: "#252529"),
        codeBorder: NSColor(hex: "#323238"),
        quoteBar: NSColor(hex: "#3C3C43"),
        quoteText: NSColor(hex: "#B0B0B8"),
        rule: NSColor(hex: "#323238"),
        selection: NSColor(hex: "#0A4A8F"),
        cursor: NSColor(hex: "#0A84FF"),
        tableBorder: NSColor(hex: "#323238"),
        tableHeaderBackground: NSColor(hex: "#26262B"),
        tableStripe: NSColor(hex: "#202024"),
        highlightBackground: NSColor(hex: "#6B5717"),
        taskDone: NSColor(hex: "#75757C"),
        callouts: callouts(
            note: "#64D2FF", tip: "#6FDD8B", important: "#C6A6FF",
            warning: "#FFD426", caution: "#FF6961", tint: 0.14),
        genericCallout: CalloutColors(
            accent: NSColor(hex: "#98989F"), background: NSColor(hex: "#98989F", alpha: 0.10)),
        isTranslucent: true,
        pageAlpha: 0.22,
        material: .sidebar
    )

    static let all: [ColorTheme] = [
        paper, ink, sepia, nord, frost, onyx, contrastLight, contrastDark,
    ]

    static func theme(id: String) -> ColorTheme? { all.first { $0.id == id } }
}
