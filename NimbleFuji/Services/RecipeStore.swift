import Foundation
import Observation

/// Loads and saves recipes as YAML files in a folder.
@Observable
final class RecipeStore {
    struct LoadProblem: Identifiable, Hashable {
        var id: URL { file }
        let file: URL
        let message: String
    }

    private(set) var recipes: [Recipe] = []
    private(set) var problems: [LoadProblem] = []
    private(set) var folder: URL
    private var files: [Recipe.ID: URL] = [:]

    static let folderDefaultsKey = "recipesFolderPath"
    private static let seededDefaultsKey = "didSeedSampleRecipes"

    static var defaultFolder: URL {
        URL.applicationSupportDirectory
            .appending(path: "Nimble Fuji", directoryHint: .isDirectory)
            .appending(path: "Recipes", directoryHint: .isDirectory)
    }

    init(folder: URL? = nil) {
        if let folder {
            self.folder = folder
        } else if let path = UserDefaults.standard.string(forKey: Self.folderDefaultsKey), !path.isEmpty {
            self.folder = URL(filePath: path, directoryHint: .isDirectory)
        } else {
            self.folder = Self.defaultFolder
        }
    }

    func fileURL(for recipe: Recipe) -> URL? { files[recipe.id] }

    func recipe(withID id: Recipe.ID?) -> Recipe? {
        guard let id else { return nil }
        return recipes.first { $0.id == id }
    }

    // MARK: Loading

    func changeFolder(to url: URL) {
        folder = url
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: Self.folderDefaultsKey)
        reload()
    }

    func reload(seedIfNeeded: Bool = false) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        if seedIfNeeded, !UserDefaults.standard.bool(forKey: Self.seededDefaultsKey) {
            seedSamples()
            UserDefaults.standard.set(true, forKey: Self.seededDefaultsKey)
        }

        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Recipe] = []
        var newFiles: [Recipe.ID: URL] = [:]
        var newProblems: [LoadProblem] = []

        // Keep IDs stable across reloads so selections survive.
        let previousIDs = Dictionary(uniqueKeysWithValues: files.map { ($0.value.standardizedFileURL, $0.key) })

        for url in urls where ["yaml", "yml"].contains(url.pathExtension.lowercased()) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                var recipe = try Recipe.fromYAML(text)
                if let id = previousIDs[url.standardizedFileURL] { recipe.id = id }
                loaded.append(recipe)
                newFiles[recipe.id] = url
            } catch {
                newProblems.append(LoadProblem(file: url, message: Self.describe(error)))
            }
        }
        recipes = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files = newFiles
        problems = newProblems.sorted { $0.file.lastPathComponent < $1.file.lastPathComponent }
    }

    private func seedSamples() {
        for yaml in SampleRecipes.yaml {
            guard let recipe = try? Recipe.fromYAML(yaml) else { continue }
            let url = uniqueURL(for: recipe, excluding: nil)
            try? yaml.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Editing

    /// Saves the recipe, renaming its file when the name changed.
    @discardableResult
    func save(_ recipe: Recipe) throws -> Recipe {
        let yaml = try recipe.toYAML()
        let existing = files[recipe.id]
        let desiredName = recipe.slug + ".yaml"
        let target: URL
        if let existing, existing.lastPathComponent == desiredName {
            target = existing
        } else {
            target = uniqueURL(for: recipe, excluding: existing)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try yaml.write(to: target, atomically: true, encoding: .utf8)
        if let existing, existing != target {
            try? FileManager.default.removeItem(at: existing)
        }
        files[recipe.id] = target
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.append(recipe)
        }
        recipes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return recipe
    }

    func create(named name: String = "New Recipe") throws -> Recipe {
        var recipe = Recipe(name: uniqueName(name))
        recipe.filmSimulation = .provia
        return try save(recipe)
    }

    func duplicate(_ recipe: Recipe) throws -> Recipe {
        var copy = recipe
        copy.id = UUID()
        copy.name = uniqueName(recipe.name + " copy")
        return try save(copy)
    }

    /// Moves the recipe's file to the Trash.
    func delete(_ recipe: Recipe) throws {
        if let url = files[recipe.id] {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        files[recipe.id] = nil
        recipes.removeAll { $0.id == recipe.id }
    }

    /// Copies YAML files into the recipes folder after checking they parse.
    func importFiles(_ urls: [URL]) -> [String] {
        var errors: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                var recipe = try Recipe.fromYAML(text)
                recipe.name = uniqueName(recipe.name)
                try save(recipe)
            } catch {
                errors.append("\(url.lastPathComponent): \(Self.describe(error))")
            }
        }
        return errors
    }

    // MARK: Helpers

    func uniqueName(_ base: String) -> String {
        let names = Set(recipes.map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var n = 2
        while names.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    private func uniqueURL(for recipe: Recipe, excluding current: URL?) -> URL {
        let fm = FileManager.default
        var candidate = folder.appending(path: recipe.slug + ".yaml")
        var n = 2
        while fm.fileExists(atPath: candidate.path(percentEncoded: false)), candidate != current {
            candidate = folder.appending(path: "\(recipe.slug)-\(n).yaml")
            n += 1
        }
        return candidate
    }

    static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case let .dataCorrupted(context), let .typeMismatch(_, context), let .valueNotFound(_, context), let .keyNotFound(_, context):
                return context.debugDescription
            @unknown default:
                break
            }
        }
        return error.localizedDescription
    }
}
