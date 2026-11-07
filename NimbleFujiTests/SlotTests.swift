import Foundation
import Testing
@testable import Nimble_Fuji

@MainActor
struct SlotTests {
    /// Real `fujicli --json simulation get c1` output from the X-T5.
    static let leicaRealJSON = #"{"customSettingName":"Leica Real","imageSize":"7728x5152","imageQuality":"fine","filmSimulation":"reala_ace","grainEffect":"off","colorChromeEffect":"strong","colorChromeFxBlue":"weak","whiteBalance":"auto","whiteBalanceShiftRed":2,"whiteBalanceShiftBlue":-1,"highlightTone":-1.0,"shadowTone":0.0,"color":3,"sharpness":0,"noiseReduction":0,"clarity":0,"lensModulationOptimizer":"on","colorSpace":"adobe_rgb","dynamicRange":"hdr200","dynamicRangePriority":"off","smoothSkinEffect":"off"}"#

    @Test func parsesFujicliSlotJSON() throws {
        let recipe = try Recipe(fujicliJSON: Data(Self.leicaRealJSON.utf8))
        #expect(recipe.name == "Leica Real")
        #expect(recipe.filmSimulation == .realaAce)
        #expect(recipe.grainEffect == .off)
        #expect(recipe.colorChromeEffect == .strong)
        #expect(recipe.colorChromeFXBlue == .weak)
        #expect(recipe.whiteBalance == .auto)
        #expect(recipe.whiteBalanceShiftRed == 2)
        #expect(recipe.whiteBalanceShiftBlue == -1)
        #expect(recipe.dynamicRange == .dr200)
        #expect(recipe.dynamicRangePriority == .off)
        #expect(recipe.highlightTone == -1)
        #expect(recipe.color == 3)
        #expect(recipe.isValid)
    }

    @Test func slotWriteFillsEverySetting() {
        var recipe = Recipe(name: "Sparse")
        recipe.filmSimulation = .classicChrome
        recipe.exposureOffset = 0.33
        let args = FujiCLI.slotArguments(slot: 4, recipe: recipe)
        #expect(args.prefix(3) == ["simulation", "set", "c4"])
        #expect(args.contains("--custom-setting-name=Sparse"))
        #expect(args.contains("--grain-effect=off"))
        #expect(args.contains("--white-balance=auto"))
        #expect(args.contains("--white-balance-shift-red=0"))
        #expect(args.contains("--dynamic-range-priority=off"))
        #expect(args.contains("--highlight-tone=0"))
        #expect(args.contains("--clarity=0"))
        #expect(!args.contains { $0.hasPrefix("--exposure-offset") })
        #expect(!args.contains { $0.hasPrefix("--monochromatic") })
        #expect(recipe.forSlot().isValid)
    }

    @Test func dRangePriorityOmitsToneSettings() {
        var recipe = Recipe(name: "DRP")
        recipe.dynamicRangePriority = .strong
        let filled = recipe.forSlot()
        #expect(filled.highlightTone == nil && filled.shadowTone == nil && filled.dynamicRange == nil)
        #expect(filled.isValid)
    }

    @Test func slotNamesFitTheCamera() {
        #expect(Recipe.slotName(for: "Leica Real") == "Leica Real")
        #expect(Recipe.slotName(for: "Café   Crème / Night") == "Cafe Creme Night")
        #expect(Recipe.slotName(for: String(repeating: "A", count: 40)).count == 25)
    }

    @Test func roundTripSlotToRecipe() throws {
        let slot = try Recipe(fujicliJSON: Data(Self.leicaRealJSON.utf8))
        // Writing back what was read must not change any setting.
        #expect(slot.forSlot().hasSameContent(as: slot))
    }

    @Test func recipeMapsToFujiKitSettings() throws {
        var recipe = try Recipe(fujicliJSON: Data(Self.leicaRealJSON.utf8))
        recipe.exposureOffset = 1.0 / 3.0
        let s = recipe.cameraSettings()
        #expect(s.filmSimulation == "reala-ace")
        #expect(s.grainEffect == "off")
        #expect(s.dynamicRange == "hdr200")
        #expect(s.whiteBalance == "auto" && s.whiteBalanceTemperature == nil)
        #expect(s.color == 3 && s.highlightTone == -1)
        #expect(s.fileType == "jpeg")
        // FujiKit's JSON is what the app's slot parser reads back.
        let roundTrip = try Recipe(fujicliJSON: JSONEncoder().encode(s))
        #expect(roundTrip.filmSimulation == .realaAce && roundTrip.dynamicRange == .dr200)
    }
}
