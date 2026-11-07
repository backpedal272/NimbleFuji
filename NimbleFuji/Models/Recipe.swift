import Foundation

/// A film-simulation recipe. Every setting is optional: a setting that isn't set
/// keeps the value the RAW file was shot with.
nonisolated struct Recipe: Identifiable, Hashable, Sendable {
    var id = UUID()

    var name: String
    var notes: String?
    var source: String?

    var filmSimulation: FilmSimulation?
    var monochromaticColorWarmCool: Int?
    var monochromaticColorMagentaGreen: Int?
    var grainEffect: GrainEffect?
    var colorChromeEffect: EffectStrength?
    var colorChromeFXBlue: EffectStrength?

    var whiteBalance: WhiteBalanceMode?
    var whiteBalanceTemperature: Int?
    var whiteBalanceShiftRed: Int?
    var whiteBalanceShiftBlue: Int?

    var dynamicRange: DynamicRange?
    var dynamicRangePriority: DynamicRangePriority?
    var highlightTone: Double?
    var shadowTone: Double?

    var color: Int?
    var sharpness: Int?
    var noiseReduction: Int?
    var clarity: Int?
    var smoothSkinEffect: EffectStrength?

    var exposureOffset: Double?

    init(name: String) {
        self.name = name
    }

    /// Two recipes match when every setting matches; `id` is ignored.
    func hasSameContent(as other: Recipe) -> Bool {
        var copy = other
        copy.id = id
        return copy == self
    }
}

// MARK: - Validation

nonisolated extension Recipe {
    func validationIssues() -> [String] {
        var issues: [String] = []
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { issues.append("The recipe needs a name.") }

        func check(_ value: Double?, _ rule: NumericRule, _ label: String) {
            guard let value, !rule.contains(value) else { return }
            issues.append("\(label) must be between \(Self.format(rule.min, signed: true)) and \(Self.format(rule.max, signed: true)) in steps of \(Self.format(rule.step, signed: false)).")
        }
        check(highlightTone, .tone, "Highlight")
        check(shadowTone, .tone, "Shadow")
        check(color.map(Double.init), .fourSteps, "Color")
        check(sharpness.map(Double.init), .fourSteps, "Sharpness")
        check(noiseReduction.map(Double.init), .fourSteps, "High ISO NR")
        check(clarity.map(Double.init), .clarity, "Clarity")
        check(whiteBalanceShiftRed.map(Double.init), .wbShift, "WB shift red")
        check(whiteBalanceShiftBlue.map(Double.init), .wbShift, "WB shift blue")
        check(monochromaticColorWarmCool.map(Double.init), .monochromatic, "Monochromatic WC")
        check(monochromaticColorMagentaGreen.map(Double.init), .monochromatic, "Monochromatic MG")

        if let exposureOffset, !(-3.0...3.0).contains(exposureOffset) {
            issues.append("Exposure must be between -3 and +3 EV.")
        }

        if whiteBalance == .temperature {
            if let k = whiteBalanceTemperature {
                check(Double(k), .kelvin, "Color temperature")
            } else {
                issues.append("Kelvin white balance needs a temperature, e.g. 5500K.")
            }
        }

        if let drp = dynamicRangePriority, drp != .off, highlightTone != nil || shadowTone != nil {
            issues.append("Highlight and Shadow can't be set while D-Range Priority is on.")
        }
        if let drp = dynamicRangePriority, drp != .off, let dr = dynamicRange, dr != .auto {
            issues.append("Dynamic Range can't be set while D-Range Priority is on.")
        }

        if let sim = filmSimulation, !sim.isMonochrome,
           monochromaticColorWarmCool != nil || monochromaticColorMagentaGreen != nil {
            issues.append("Monochromatic Color only applies to Acros and Monochrome simulations.")
        }
        return issues
    }

    var isValid: Bool { validationIssues().isEmpty }

    static func format(_ value: Double, signed: Bool) -> String {
        let text: String
        if value == value.rounded() {
            text = String(Int(value))
        } else if abs(value * 2 - (value * 2).rounded()) < 1e-9 {
            text = String(format: "%.1f", value)
        } else {
            text = String(format: "%.2f", value)
        }
        return signed && value > 0 ? "+" + text : text
    }
}

// MARK: - fujicli

nonisolated extension Recipe {
    /// `image render` option flags for this recipe. Uses `--flag=value` so
    /// negative numbers are never mistaken for options.
    func fujicliFlags() -> [String] {
        var flags: [String] = []
        func add(_ flag: String, _ value: String?) {
            if let value { flags.append("--\(flag)=\(value)") }
        }
        func number(_ value: Double?) -> String? { value.map { Self.format($0, signed: false) } }
        func number(_ value: Int?) -> String? { value.map(String.init) }

        add("film-simulation", filmSimulation?.rawValue)
        add("monochromatic-color-temperature", number(monochromaticColorWarmCool))
        add("monochromatic-color-tint", number(monochromaticColorMagentaGreen))
        add("grain-effect", grainEffect?.rawValue)
        add("color-chrome-effect", colorChromeEffect?.rawValue)
        add("color-chrome-fx-blue", colorChromeFXBlue?.rawValue)

        add("white-balance", whiteBalance?.rawValue)
        if whiteBalance == .temperature {
            add("white-balance-temperature", number(whiteBalanceTemperature))
        }
        add("white-balance-shift-red", number(whiteBalanceShiftRed))
        add("white-balance-shift-blue", number(whiteBalanceShiftBlue))

        add("dynamic-range", dynamicRange?.rawValue)
        add("dynamic-range-priority", dynamicRangePriority?.rawValue)
        add("highlight-tone", number(highlightTone))
        add("shadow-tone", number(shadowTone))

        add("color", number(color))
        add("sharpness", number(sharpness))
        add("noise-reduction", number(noiseReduction))
        add("clarity", number(clarity))
        add("smooth-skin-effect", smoothSkinEffect?.rawValue)

        add("exposure-offset", number(exposureOffset))
        return flags
    }

    /// Short description shown under the recipe name.
    var summary: String {
        var parts: [String] = []
        if let filmSimulation { parts.append(filmSimulation.label) }
        if let dynamicRange { parts.append(dynamicRange.label) }
        if let whiteBalance {
            if whiteBalance == .temperature, let k = whiteBalanceTemperature {
                parts.append("\(k)K")
            } else {
                parts.append(whiteBalance.label)
            }
        }
        return parts.isEmpty ? "As shot" : parts.joined(separator: " · ")
    }

    /// A filename-safe version of the name, used for YAML files and JPG suffixes.
    var slug: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "Recipe" : collapsed
    }
}
