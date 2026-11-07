import Foundation
import Yams

/// YAML format, close to how Fuji X Weekly writes recipes:
///
/// ```yaml
/// name: CLAUTRA 800
/// comment: My go-to for warm evening light; I lowered the grain.
/// film_simulation: Classic Chrome
/// grain: Strong Large
/// color_chrome_effect: Weak
/// color_chrome_fx_blue: Off
/// white_balance: 6300K
/// wb_shift_red: 1
/// wb_shift_blue: -3
/// dynamic_range: DR400
/// highlight: -1.5
/// shadow: -0.5
/// color: +2
/// sharpness: -2
/// high_iso_nr: -4
/// clarity: -2
/// source: https://…
/// notes: Built from the Portra 800 v3 recipe on Fuji X Weekly.
/// ```
nonisolated extension Recipe: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, comment, notes, source
        case filmSimulation = "film_simulation"
        case monochromaticColorWarmCool = "monochromatic_color_wc"
        case monochromaticColorMagentaGreen = "monochromatic_color_mg"
        case grainEffect = "grain"
        case colorChromeEffect = "color_chrome_effect"
        case colorChromeFXBlue = "color_chrome_fx_blue"
        case whiteBalance = "white_balance"
        case whiteBalanceShiftRed = "wb_shift_red"
        case whiteBalanceShiftBlue = "wb_shift_blue"
        case dynamicRange = "dynamic_range"
        case dynamicRangePriority = "d_range_priority"
        case highlightTone = "highlight"
        case shadowTone = "shadow"
        case color
        case sharpness
        case noiseReduction = "high_iso_nr"
        case clarity
        case smoothSkinEffect = "smooth_skin"
        case exposureOffset = "exposure"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled")
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        source = try c.decodeIfPresent(String.self, forKey: .source)

        filmSimulation = try c.choice(.filmSimulation)
        monochromaticColorWarmCool = try c.integer(.monochromaticColorWarmCool)
        monochromaticColorMagentaGreen = try c.integer(.monochromaticColorMagentaGreen)
        grainEffect = try c.choice(.grainEffect)
        colorChromeEffect = try c.choice(.colorChromeEffect)
        colorChromeFXBlue = try c.choice(.colorChromeFXBlue)

        if let wb = try c.text(.whiteBalance) {
            let compact = wb.replacingOccurrences(of: " ", with: "").uppercased()
            if compact.hasSuffix("K"), let kelvin = Int(compact.dropLast()) {
                whiteBalance = .temperature
                whiteBalanceTemperature = kelvin
            } else if let mode = WhiteBalanceMode.parse(wb) {
                whiteBalance = mode
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .whiteBalance, in: c,
                    debugDescription: "Unknown white_balance “\(wb)”. Use a Kelvin value like 5500K or one of: \(WhiteBalanceMode.validLabels)")
            }
        }
        whiteBalanceShiftRed = try c.integer(.whiteBalanceShiftRed)
        whiteBalanceShiftBlue = try c.integer(.whiteBalanceShiftBlue)

        dynamicRange = try c.choice(.dynamicRange)
        dynamicRangePriority = try c.choice(.dynamicRangePriority)
        highlightTone = try c.number(.highlightTone)
        shadowTone = try c.number(.shadowTone)

        color = try c.integer(.color)
        sharpness = try c.integer(.sharpness)
        noiseReduction = try c.integer(.noiseReduction)
        clarity = try c.integer(.clarity)
        smoothSkinEffect = try c.choice(.smoothSkinEffect)
        exposureOffset = try c.number(.exposureOffset)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(comment, forKey: .comment)
        try c.encodeIfPresent(filmSimulation?.label, forKey: .filmSimulation)
        try c.encodeIfPresent(monochromaticColorWarmCool, forKey: .monochromaticColorWarmCool)
        try c.encodeIfPresent(monochromaticColorMagentaGreen, forKey: .monochromaticColorMagentaGreen)
        try c.encodeIfPresent(grainEffect?.label, forKey: .grainEffect)
        try c.encodeIfPresent(colorChromeEffect?.label, forKey: .colorChromeEffect)
        try c.encodeIfPresent(colorChromeFXBlue?.label, forKey: .colorChromeFXBlue)
        if whiteBalance == .temperature, let k = whiteBalanceTemperature {
            try c.encode("\(k)K", forKey: .whiteBalance)
        } else {
            try c.encodeIfPresent(whiteBalance?.label, forKey: .whiteBalance)
        }
        try c.encodeIfPresent(whiteBalanceShiftRed, forKey: .whiteBalanceShiftRed)
        try c.encodeIfPresent(whiteBalanceShiftBlue, forKey: .whiteBalanceShiftBlue)
        try c.encodeIfPresent(dynamicRange?.label, forKey: .dynamicRange)
        try c.encodeIfPresent(dynamicRangePriority?.label, forKey: .dynamicRangePriority)
        try c.encodeIfPresent(highlightTone, forKey: .highlightTone)
        try c.encodeIfPresent(shadowTone, forKey: .shadowTone)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(sharpness, forKey: .sharpness)
        try c.encodeIfPresent(noiseReduction, forKey: .noiseReduction)
        try c.encodeIfPresent(clarity, forKey: .clarity)
        try c.encodeIfPresent(smoothSkinEffect?.label, forKey: .smoothSkinEffect)
        try c.encodeIfPresent(exposureOffset, forKey: .exposureOffset)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(notes, forKey: .notes)
    }

    // MARK: YAML

    static func fromYAML(_ yaml: String) throws -> Recipe {
        try YAMLDecoder().decode(Recipe.self, from: yaml)
    }

    func toYAML() throws -> String {
        try YAMLEncoder().encode(self)
    }
}

private nonisolated extension KeyedDecodingContainer where Key == Recipe.CodingKeys {
    /// Any scalar, as text. YAML 1.1 reads `Off` as a boolean, so accept that too.
    func text(_ key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let bool = try? decode(Bool.self, forKey: key) { return bool ? "On" : "Off" }
        if let string = try? decode(String.self, forKey: key) { return string }
        if let double = try? decode(Double.self, forKey: key) { return String(double) }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a value for \(key.rawValue).")
    }

    func choice<T: RecipeChoice>(_ key: Key) throws -> T? {
        guard let raw = try text(key) else { return nil }
        guard let value = T.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self,
                debugDescription: "Unknown \(key.rawValue) “\(raw)”. Valid values: \(T.validLabels)")
        }
        return value
    }

    func number(_ key: Key) throws -> Double? {
        guard let raw = try text(key) else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "EV", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        if let value = Double(cleaned) { return value }
        // Allow fractions like "-1/3" for exposure.
        let parts = cleaned.split(separator: "/")
        if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 {
            return n / d
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "\(key.rawValue) must be a number, got “\(raw)”.")
    }

    func integer(_ key: Key) throws -> Int? {
        guard let value = try number(key) else { return nil }
        guard value == value.rounded() else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "\(key.rawValue) must be a whole number, got \(value).")
        }
        return Int(value)
    }
}
