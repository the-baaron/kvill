import AppKit

/// Which of the system font families a role should resolve to. Using the system
/// families means Quill ships no font files and still gets New York, SF Pro,
/// SF Rounded and SF Mono, all of which are optically sized and hinted for macOS.
enum FontFamily {
    case serif
    case sans
    case rounded
    case mono

    var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .serif: return .serif
        case .sans: return .default
        case .rounded: return .rounded
        case .mono: return .monospaced
        }
    }
}

enum FontBuilder {
    /// Resolves a system font for a family/size/weight, optionally italic.
    /// Falls back progressively so a missing design never yields a nil font.
    static func font(
        _ family: FontFamily,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        italic: Bool = false
    ) -> NSFont {
        let base: NSFont = family == .mono
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)

        var descriptor = base.fontDescriptor
        if family != .mono, let designed = descriptor.withDesign(family.design) {
            descriptor = designed
        }
        if italic {
            descriptor = descriptor.withSymbolicTraits(.italic)
        }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

struct TypographyPreset {
    let id: String
    let name: String
    /// One-line description shown in the theme switcher.
    let blurb: String

    let bodyFamily: FontFamily
    let headingFamily: FontFamily

    let bodyWeight: NSFont.Weight
    let headingWeight: NSFont.Weight

    /// Multiplier applied to the font size to get the baseline-to-baseline distance.
    let lineHeight: CGFloat
    /// Space after a paragraph, as a multiple of the base font size.
    let paragraphSpacing: CGFloat
    /// Ideal measure (text column width) as a multiple of the base font size.
    let measure: CGFloat
    /// Scale factor per heading level, index 0 == H1.
    let headingScale: [CGFloat]
    /// Extra letter spacing for body text, as a multiple of the base size.
    let bodyTracking: CGFloat

    static let all: [TypographyPreset] = [editorial, grotesk, contrast, typewriter, soft]

    static func preset(id: String) -> TypographyPreset? { all.first { $0.id == id } }

    static let editorial = TypographyPreset(
        id: "editorial",
        name: "Editorial",
        blurb: "New York throughout. Book-like, best for long reading.",
        bodyFamily: .serif,
        headingFamily: .serif,
        bodyWeight: .regular,
        headingWeight: .bold,
        lineHeight: 1.62,
        paragraphSpacing: 0.80,
        measure: 34,
        headingScale: [1.95, 1.56, 1.30, 1.13, 1.0, 0.94],
        bodyTracking: 0
    )

    static let grotesk = TypographyPreset(
        id: "grotesk",
        name: "Grotesk",
        blurb: "San Francisco throughout. Crisp and neutral.",
        bodyFamily: .sans,
        headingFamily: .sans,
        bodyWeight: .regular,
        headingWeight: .bold,
        lineHeight: 1.58,
        paragraphSpacing: 0.78,
        measure: 33,
        headingScale: [1.85, 1.50, 1.26, 1.10, 1.0, 0.93],
        bodyTracking: 0
    )

    static let contrast = TypographyPreset(
        id: "contrast",
        name: "Contrast",
        blurb: "Serif headings over a sans body. Editorial, with clear hierarchy.",
        bodyFamily: .sans,
        headingFamily: .serif,
        bodyWeight: .regular,
        headingWeight: .bold,
        lineHeight: 1.60,
        paragraphSpacing: 0.82,
        measure: 33,
        headingScale: [2.05, 1.62, 1.32, 1.12, 1.0, 0.93],
        bodyTracking: 0
    )

    static let typewriter = TypographyPreset(
        id: "typewriter",
        name: "Typewriter",
        blurb: "SF Mono throughout. Every character on the grid.",
        bodyFamily: .mono,
        headingFamily: .mono,
        bodyWeight: .regular,
        headingWeight: .bold,
        lineHeight: 1.66,
        paragraphSpacing: 0.85,
        measure: 42,
        headingScale: [1.65, 1.42, 1.24, 1.10, 1.0, 0.94],
        bodyTracking: 0
    )

    static let soft = TypographyPreset(
        id: "soft",
        name: "Soft",
        blurb: "SF Rounded throughout. Friendly and low-glare.",
        bodyFamily: .rounded,
        headingFamily: .rounded,
        bodyWeight: .regular,
        headingWeight: .semibold,
        lineHeight: 1.62,
        paragraphSpacing: 0.80,
        measure: 33,
        headingScale: [1.85, 1.50, 1.26, 1.10, 1.0, 0.93],
        bodyTracking: 0.005
    )
}

/// User-selectable base text size.
enum TextSize: String, CaseIterable {
    case small, medium, large, huge

    var points: CGFloat {
        switch self {
        case .small: return 15
        case .medium: return 17
        case .large: return 19.5
        case .huge: return 22
        }
    }

    var name: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .huge: return "Huge"
        }
    }
}

/// How wide the text column is allowed to grow, as a factor on the preset measure.
enum LineWidth: String, CaseIterable {
    case narrow, normal, wide

    var factor: CGFloat {
        switch self {
        case .narrow: return 0.84
        case .normal: return 1.0
        case .wide: return 1.22
        }
    }

    var name: String {
        switch self {
        case .narrow: return "Narrow"
        case .normal: return "Normal"
        case .wide: return "Wide"
        }
    }
}

/// Every derived measurement the layout needs, computed once per theme change.
struct Metrics {
    let base: CGFloat
    /// Width reserved to the left of the text column for hanging syntax markers.
    let gutter: CGFloat
    /// Distance between the end of a marker and the start of the text.
    let gutterGap: CGFloat
    /// Additional indent per level of list or quote nesting.
    let indentStep: CGFloat
    /// Width of the text column itself.
    let measure: CGFloat
    let lineHeight: CGFloat
    let paragraphSpacing: CGFloat
    /// Font size used for markers in the gutter.
    let markerSize: CGFloat
    /// Side of the drawn task checkbox.
    let checkboxSize: CGFloat
    /// Space between the checkbox and the text that follows it.
    let checkboxGap: CGFloat

    /// Total width of gutter plus text column.
    var contentWidth: CGFloat { gutter + measure }

    /// Horizontal space a task checkbox reserves inside the text column.
    var checkboxAdvance: CGFloat { checkboxSize + checkboxGap }

    /// Space above a rendered image.
    var imageTopPadding: CGFloat { base * 0.25 }
    /// Space below a rendered image, which holds its caption.
    var imageCaptionZone: CGFloat { base * 2.1 }

    init(preset: TypographyPreset, size: TextSize, width: LineWidth) {
        let base = size.points
        self.base = base
        self.markerSize = base * 0.84
        self.gutterGap = base * 0.62
        // Wide enough for `######` and for `100.` set in the marker font.
        self.gutter = base * 3.7
        self.indentStep = base * 1.7
        self.measure = base * preset.measure * width.factor
        self.lineHeight = base * preset.lineHeight
        self.paragraphSpacing = base * preset.paragraphSpacing
        self.checkboxSize = base * 0.92
        self.checkboxGap = base * 0.42
    }
}
