import Foundation

// MARK: - Camera slot conversion

nonisolated extension Recipe {
    /// The camera shows at most 25 characters; keep to plain ASCII so names display safely.
    static func slotName(for name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.+&()!'")
        let cleaned = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .init(identifier: "en_US"))
            .map { allowed.contains($0) ? $0 : " " }
        let collapsed = String(cleaned).split(separator: " ").joined(separator: " ")
        return String(collapsed.prefix(25))
    }

    /// The recipe as it will be stored in a slot. A slot has no “as shot”, so any
    /// setting the recipe leaves out is reset to the camera's neutral value.
    func forSlot() -> Recipe {
        var r = self
        r.filmSimulation = r.filmSimulation ?? .provia
        r.grainEffect = r.grainEffect ?? .off
        r.colorChromeEffect = r.colorChromeEffect ?? .off
        r.colorChromeFXBlue = r.colorChromeFXBlue ?? .off
        if r.whiteBalance == nil || r.whiteBalance == .asShot { r.whiteBalance = .auto }
        if r.whiteBalance == .temperature, r.whiteBalanceTemperature == nil { r.whiteBalanceTemperature = 5500 }
        r.whiteBalanceShiftRed = r.whiteBalanceShiftRed ?? 0
        r.whiteBalanceShiftBlue = r.whiteBalanceShiftBlue ?? 0
        r.dynamicRangePriority = r.dynamicRangePriority ?? .off
        if r.dynamicRangePriority == .off {
            r.dynamicRange = r.dynamicRange ?? .dr100
            r.highlightTone = r.highlightTone ?? 0
            r.shadowTone = r.shadowTone ?? 0
        } else {
            r.dynamicRange = nil
            r.highlightTone = nil
            r.shadowTone = nil
        }
        r.color = r.color ?? 0
        r.sharpness = r.sharpness ?? 0
        r.noiseReduction = r.noiseReduction ?? 0
        r.clarity = r.clarity ?? 0
        r.smoothSkinEffect = r.smoothSkinEffect ?? .off
        if r.filmSimulation?.isMonochrome == true {
            r.monochromaticColorWarmCool = r.monochromaticColorWarmCool ?? 0
            r.monochromaticColorMagentaGreen = r.monochromaticColorMagentaGreen ?? 0
        } else {
            r.monochromaticColorWarmCool = nil
            r.monochromaticColorMagentaGreen = nil
        }
        r.exposureOffset = nil
        return r
    }

    /// Builds a recipe from `fujicli --json simulation get` output.
    init(fujicliJSON data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        func text(_ key: String) -> String? { json[key].map { "\($0)" } }
        func int(_ key: String) -> Int? { (json[key] as? NSNumber)?.intValue }
        func double(_ key: String) -> Double? { (json[key] as? NSNumber)?.doubleValue }
        func choice<T: RecipeChoice>(_ key: String) -> T? { text(key).flatMap(T.parse) }

        self.init(name: text("customSettingName") ?? "")
        filmSimulation = choice("filmSimulation")
        monochromaticColorWarmCool = int("monochromaticColorTemperature")
        monochromaticColorMagentaGreen = int("monochromaticColorTint")
        grainEffect = choice("grainEffect")
        colorChromeEffect = choice("colorChromeEffect")
        colorChromeFXBlue = choice("colorChromeFxBlue")
        whiteBalance = choice("whiteBalance")
        whiteBalanceTemperature = int("whiteBalanceTemperature")
        if whiteBalance != .temperature { whiteBalanceTemperature = nil }
        whiteBalanceShiftRed = int("whiteBalanceShiftRed")
        whiteBalanceShiftBlue = int("whiteBalanceShiftBlue")
        dynamicRange = choice("dynamicRange")
        dynamicRangePriority = choice("dynamicRangePriority")
        highlightTone = double("highlightTone")
        shadowTone = double("shadowTone")
        color = int("color")
        sharpness = int("sharpness")
        noiseReduction = int("noiseReduction")
        clarity = int("clarity")
        smoothSkinEffect = choice("smoothSkinEffect")
    }

    /// Settings as label/value pairs, for showing and comparing recipes.
    var settingRows: [(label: String, value: String)] {
        func signed(_ v: Double?) -> String { v.map { Recipe.format($0, signed: true) } ?? "—" }
        func signed(_ v: Int?) -> String { signed(v.map(Double.init)) }
        var rows: [(String, String)] = [
            ("Film Simulation", filmSimulation?.label ?? "—"),
        ]
        if filmSimulation?.isMonochrome == true {
            rows.append(("Monochromatic WC", signed(monochromaticColorWarmCool)))
            rows.append(("Monochromatic MG", signed(monochromaticColorMagentaGreen)))
        }
        let wb: String = {
            guard let whiteBalance else { return "—" }
            if whiteBalance == .temperature { return whiteBalanceTemperature.map { "\($0)K" } ?? "Kelvin" }
            return whiteBalance.label
        }()
        rows += [
            ("Grain", grainEffect?.label ?? "—"),
            ("Color Chrome", colorChromeEffect?.label ?? "—"),
            ("Color Chrome FX Blue", colorChromeFXBlue?.label ?? "—"),
            ("White Balance", wb),
            ("WB Shift", "R\(signed(whiteBalanceShiftRed)) B\(signed(whiteBalanceShiftBlue))"),
            ("Dynamic Range", dynamicRange?.label ?? "—"),
            ("D-Range Priority", dynamicRangePriority?.label ?? "—"),
            ("Highlight", signed(highlightTone)),
            ("Shadow", signed(shadowTone)),
            ("Color", signed(color)),
            ("Sharpness", signed(sharpness)),
            ("High ISO NR", signed(noiseReduction)),
            ("Clarity", signed(clarity)),
            ("Smooth Skin", smoothSkinEffect?.label ?? "—"),
        ]
        return rows
    }
}
