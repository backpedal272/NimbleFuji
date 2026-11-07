import Foundation
import Testing
@testable import Nimble_Fuji

@MainActor
struct RecipeTests {
    @Test func parsesReadableYAML() throws {
        let recipe = try Recipe.fromYAML("""
        name: CLAUTRA 800
        film_simulation: Classic Chrome
        grain: Strong, Large
        color_chrome_effect: Weak
        color_chrome_fx_blue: Off
        white_balance: 6300K
        wb_shift_red: +1
        wb_shift_blue: -3
        dynamic_range: DR400
        highlight: -1.5
        shadow: -0.5
        color: +2
        sharpness: -2
        high_iso_nr: -4
        clarity: -2
        smooth_skin: Off
        exposure: -1/3
        """)
        #expect(recipe.name == "CLAUTRA 800")
        #expect(recipe.filmSimulation == .classicChrome)
        #expect(recipe.grainEffect == .strongLarge)
        #expect(recipe.colorChromeFXBlue == .off)
        #expect(recipe.whiteBalance == .temperature)
        #expect(recipe.whiteBalanceTemperature == 6300)
        #expect(recipe.whiteBalanceShiftRed == 1)
        #expect(recipe.dynamicRange == .dr400)
        #expect(recipe.highlightTone == -1.5)
        #expect(recipe.color == 2)
        #expect(recipe.smoothSkinEffect == .off)
        #expect(abs((recipe.exposureOffset ?? 0) + 1.0 / 3.0) < 1e-9)
        #expect(recipe.isValid)
    }

    @Test func roundTripsThroughYAML() throws {
        var recipe = Recipe(name: "Round Trip")
        recipe.filmSimulation = .acrosR
        recipe.monochromaticColorWarmCool = -3
        recipe.whiteBalance = .daylight
        recipe.dynamicRange = .dr200
        recipe.shadowTone = 1.5
        recipe.clarity = 3
        recipe.colorChromeEffect = .off
        let yaml = try recipe.toYAML()
        let decoded = try Recipe.fromYAML(yaml)
        #expect(decoded.hasSameContent(as: recipe), "YAML was:\n\(yaml)")
    }

    @Test func keepsCommentAndNotesSeparate() throws {
        let recipe = try Recipe.fromYAML("name: Two\ncomment: Use for portraits\nnotes: From Fuji X Weekly")
        #expect(recipe.comment == "Use for portraits")
        #expect(recipe.notes == "From Fuji X Weekly")
        let yaml = try recipe.toYAML()
        let lines = yaml.split(separator: "\n").map(String.init)
        #expect(lines.first == "name: Two")
        #expect(lines.dropFirst().first == "comment: Use for portraits", "comment follows the name")
        #expect(lines.last == "notes: From Fuji X Weekly")
    }

    @Test func multilineCommentRoundTrips() throws {
        var recipe = Recipe(name: "Story")
        recipe.comment = "Started from Portra 800 v3.\nWarmed it up for indoor light."
        let decoded = try Recipe.fromYAML(try recipe.toYAML())
        #expect(decoded.comment == recipe.comment)
    }

    @Test func acceptsAliasesAndTokens() {
        #expect(FilmSimulation.parse("classic-chrome") == .classicChrome)
        #expect(FilmSimulation.parse("Classic Neg.") == .classicNegative)
        #expect(FilmSimulation.parse("ACROS + Ye") == .acrosYe)
        #expect(DynamicRange.parse("400") == .dr400)
        #expect(DynamicRange.parse("hdr800-plus") == .hdr800Plus)
        #expect(WhiteBalanceMode.parse("Fluorescent 3") == .fluorescent3)
        #expect(GrainEffect.parse("Large Weak") == .weakLarge)
    }

    @Test func rejectsUnknownValues() {
        #expect(throws: DecodingError.self) {
            try Recipe.fromYAML("name: Bad\nfilm_simulation: Kodachrome")
        }
    }

    @Test func buildsFujicliFlags() {
        var recipe = Recipe(name: "Flags")
        recipe.filmSimulation = .classicChrome
        recipe.whiteBalance = .temperature
        recipe.whiteBalanceTemperature = 6300
        recipe.highlightTone = -1.5
        recipe.color = 2
        recipe.grainEffect = .strongLarge
        #expect(recipe.fujicliFlags() == [
            "--film-simulation=classic-chrome",
            "--grain-effect=strong-large",
            "--white-balance=temperature",
            "--white-balance-temperature=6300",
            "--highlight-tone=-1.5",
            "--color=2",
        ])
    }

    @Test func emptyRecipeRendersAsShot() {
        let args = FujiCLI.renderArguments(
            input: URL(filePath: "/tmp/in.RAF"), output: URL(filePath: "/tmp/out.jpg"),
            recipe: Recipe(name: "Plain"), draft: false)
        #expect(args == ["image", "render", "--file-type=jpeg", "/tmp/in.RAF", "/tmp/out.jpg"])
    }

    @Test func validatesRangesAndConflicts() {
        var recipe = Recipe(name: "Invalid")
        recipe.highlightTone = 4.5
        recipe.color = 1
        #expect(!recipe.isValid)
        recipe.highlightTone = 1.25
        #expect(!recipe.isValid)
        recipe.highlightTone = 1.5
        #expect(recipe.isValid)
        recipe.dynamicRangePriority = .strong
        #expect(!recipe.isValid)
    }

    @Test func outputNamesUseRawAndRecipe() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rawURL = folder.appending(path: "DSCF0001.RAF")
        try Data().write(to: rawURL)
        let raw = try #require(RawFile(url: rawURL))
        let recipe = Recipe(name: "CLAUTRA 800")

        let first = BatchRenderer.outputURL(for: raw, recipe: recipe, in: folder, overwrite: false)
        #expect(first.lastPathComponent == "DSCF0001_CLAUTRA-800.jpg")
        try Data().write(to: first)
        let second = BatchRenderer.outputURL(for: raw, recipe: recipe, in: folder, overwrite: false)
        #expect(second.lastPathComponent == "DSCF0001_CLAUTRA-800-2.jpg")
        let overwritten = BatchRenderer.outputURL(for: raw, recipe: recipe, in: folder, overwrite: true)
        #expect(overwritten == first)
    }

    @Test func sampleRecipesAreValid() throws {
        for yaml in SampleRecipes.yaml {
            let recipe = try Recipe.fromYAML(yaml)
            #expect(recipe.isValid, "\(recipe.name): \(recipe.validationIssues())")
        }
    }
}
