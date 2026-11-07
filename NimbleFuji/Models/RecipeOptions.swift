import Foundation

/// A named camera setting value. `rawValue` is the token fujicli expects on the
/// command line; `label` is the human-readable name written to YAML.
nonisolated protocol RecipeChoice: RawRepresentable, CaseIterable, Hashable, Sendable, Identifiable
where RawValue == String, AllCases: RandomAccessCollection {
    var label: String { get }
    /// Extra accepted spellings, keyed by `RecipeText.normalize(_:)` output.
    static var aliases: [String: Self] { get }
    /// Shown in YAML error messages.
    static var settingName: String { get }
}

nonisolated extension RecipeChoice {
    var id: String { rawValue }
    static var aliases: [String: Self] { [:] }

    /// Lenient parsing: accepts the label, the fujicli token or an alias,
    /// ignoring case, spaces, punctuation and hyphens.
    static func parse(_ text: String) -> Self? {
        let key = RecipeText.normalize(text)
        if let alias = aliases[key] { return alias }
        return allCases.first {
            RecipeText.normalize($0.rawValue) == key || RecipeText.normalize($0.label) == key
        }
    }

    static var validLabels: String { allCases.map(\.label).joined(separator: ", ") }
}

nonisolated enum RecipeText {
    static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "+" })
    }
}

nonisolated enum FilmSimulation: String, RecipeChoice {
    case provia, velvia, astia
    case proNegHi = "pro-neg-hi"
    case proNegStd = "pro-neg-std"
    case classicChrome = "classic-chrome"
    case classicNegative = "classic-negative"
    case nostalgicNegative = "nostalgic-negative"
    case realaAce = "reala-ace"
    case eterna
    case eternaBleachBypass = "eterna-bleach-bypass"
    case acros
    case acrosYe = "acros-ye"
    case acrosR = "acros-r"
    case acrosG = "acros-g"
    case monochrome
    case monochromeYe = "monochrome-ye"
    case monochromeR = "monochrome-r"
    case monochromeG = "monochrome-g"
    case sepia

    static let settingName = "film_simulation"

    var label: String {
        switch self {
        case .provia: "Provia"
        case .velvia: "Velvia"
        case .astia: "Astia"
        case .proNegHi: "PRO Neg. Hi"
        case .proNegStd: "PRO Neg. Std"
        case .classicChrome: "Classic Chrome"
        case .classicNegative: "Classic Negative"
        case .nostalgicNegative: "Nostalgic Negative"
        case .realaAce: "Reala Ace"
        case .eterna: "Eterna"
        case .eternaBleachBypass: "Eterna Bleach Bypass"
        case .acros: "Acros"
        case .acrosYe: "Acros + Ye"
        case .acrosR: "Acros + R"
        case .acrosG: "Acros + G"
        case .monochrome: "Monochrome"
        case .monochromeYe: "Monochrome + Ye"
        case .monochromeR: "Monochrome + R"
        case .monochromeG: "Monochrome + G"
        case .sepia: "Sepia"
        }
    }

    static let aliases: [String: FilmSimulation] = [
        "standard": .provia, "proviastandard": .provia,
        "vivid": .velvia, "velviavivid": .velvia,
        "soft": .astia, "astiasoft": .astia,
        "classicneg": .classicNegative,
        "nostalgicneg": .nostalgicNegative,
        "eternacinema": .eterna,
        "bleachbypass": .eternaBleachBypass,
        "acrosy": .acrosYe, "acrosyellow": .acrosYe, "acrosred": .acrosR, "acrosgreen": .acrosG,
        "monochromey": .monochromeYe, "monochromeyellow": .monochromeYe,
        "monochromered": .monochromeR, "monochromegreen": .monochromeG,
    ]

    var isMonochrome: Bool {
        switch self {
        case .acros, .acrosYe, .acrosR, .acrosG, .monochrome, .monochromeYe, .monochromeR, .monochromeG:
            true
        default:
            false
        }
    }
}

nonisolated enum GrainEffect: String, RecipeChoice {
    case off
    case weakSmall = "weak-small"
    case strongSmall = "strong-small"
    case weakLarge = "weak-large"
    case strongLarge = "strong-large"

    static let settingName = "grain"

    var label: String {
        switch self {
        case .off: "Off"
        case .weakSmall: "Weak Small"
        case .strongSmall: "Strong Small"
        case .weakLarge: "Weak Large"
        case .strongLarge: "Strong Large"
        }
    }

    static let aliases: [String: GrainEffect] = [
        "smallweak": .weakSmall, "smallstrong": .strongSmall,
        "largeweak": .weakLarge, "largestrong": .strongLarge,
    ]
}

/// Off / Weak / Strong, used by Color Chrome Effect, Color Chrome FX Blue and Smooth Skin.
nonisolated enum EffectStrength: String, RecipeChoice {
    case off, weak, strong

    static let settingName = "effect"

    var label: String {
        switch self {
        case .off: "Off"
        case .weak: "Weak"
        case .strong: "Strong"
        }
    }
}

nonisolated enum DynamicRange: String, RecipeChoice {
    case auto
    case dr100 = "hdr100"
    case dr200 = "hdr200"
    case dr400 = "hdr400"
    case hdr800 = "hdr800"
    case hdr800Plus = "hdr800-plus"

    static let settingName = "dynamic_range"

    var label: String {
        switch self {
        case .auto: "Auto"
        case .dr100: "DR100"
        case .dr200: "DR200"
        case .dr400: "DR400"
        case .hdr800: "HDR800"
        case .hdr800Plus: "HDR800+"
        }
    }

    static let aliases: [String: DynamicRange] = [
        "100": .dr100, "200": .dr200, "400": .dr400,
        "dr100%": .dr100, "dr200%": .dr200, "dr400%": .dr400,
        "800": .hdr800, "800+": .hdr800Plus,
    ]
}

nonisolated enum DynamicRangePriority: String, RecipeChoice {
    case off, auto, weak, strong, plus

    static let settingName = "d_range_priority"

    var label: String {
        switch self {
        case .off: "Off"
        case .auto: "Auto"
        case .weak: "Weak"
        case .strong: "Strong"
        case .plus: "Plus"
        }
    }
}

nonisolated enum WhiteBalanceMode: String, RecipeChoice {
    case asShot = "as-shot"
    case auto
    case whitePriority = "white-priority"
    case ambiencePriority = "ambience-priority"
    case temperature
    case daylight, shade
    case fluorescent1, fluorescent2, fluorescent3
    case incandescent, underwater
    case custom1, custom2, custom3

    static let settingName = "white_balance"

    var label: String {
        switch self {
        case .asShot: "As Shot"
        case .auto: "Auto"
        case .whitePriority: "Auto White Priority"
        case .ambiencePriority: "Auto Ambience Priority"
        case .temperature: "Kelvin"
        case .daylight: "Daylight"
        case .shade: "Shade"
        case .fluorescent1: "Fluorescent 1"
        case .fluorescent2: "Fluorescent 2"
        case .fluorescent3: "Fluorescent 3"
        case .incandescent: "Incandescent"
        case .underwater: "Underwater"
        case .custom1: "Custom 1"
        case .custom2: "Custom 2"
        case .custom3: "Custom 3"
        }
    }

    static let aliases: [String: WhiteBalanceMode] = [
        "aw": .auto, "awb": .auto,
        "whitepriority": .whitePriority, "ambiencepriority": .ambiencePriority,
        "k": .temperature, "colortemperature": .temperature,
        "fine": .daylight, "sunny": .daylight,
        "tungsten": .incandescent,
    ]
}

/// Numeric limits for the X-T5, mirroring fujicli's FML definitions.
nonisolated struct NumericRule: Sendable {
    let min: Double
    let max: Double
    let step: Double

    func contains(_ value: Double) -> Bool {
        guard value >= min - 1e-9, value <= max + 1e-9 else { return false }
        let steps = (value - min) / step
        return abs(steps - steps.rounded()) < 1e-6
    }

    var values: [Double] {
        stride(from: min, through: max + step / 2, by: step).map { ($0 / step).rounded() * step }
    }

    static let tone = NumericRule(min: -2, max: 4, step: 0.5)
    static let fourSteps = NumericRule(min: -4, max: 4, step: 1)
    static let clarity = NumericRule(min: -5, max: 5, step: 1)
    static let wbShift = NumericRule(min: -9, max: 9, step: 1)
    static let kelvin = NumericRule(min: 2500, max: 10000, step: 10)
    static let monochromatic = NumericRule(min: -18, max: 18, step: 1)
    static let exposure = NumericRule(min: -3, max: 3, step: 1.0 / 3.0)
}
