import AppKit
import Foundation
import Observation

enum SettingsKey {
    static let fujicliPath = "fujicliPath"
    static let outputFolderPath = "outputFolderPath"
    static let overwriteExisting = "overwriteExisting"
    static let draftRenders = "draftRenders"
    static let batchRecipeFiles = "batchRecipeFiles"
}

@Observable
final class AppModel {
    let recipes = RecipeStore()
    let library = RawLibrary()
    let renderer = BatchRenderer()
    let camera = CameraMonitor()

    /// Recipes ticked for the next batch.
    var batchRecipeIDs: Set<Recipe.ID> = [] {
        didSet { persistBatchSelection() }
    }
    /// Recipe shown in the editor.
    var editingRecipeID: Recipe.ID?
    /// RAW files selected in the table.
    var selectedRawIDs: Set<RawFile.ID> = []

    var showRenderSheet = false
    var alert: AlertInfo?

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init() {
        recipes.reload(seedIfNeeded: true)
        restoreBatchSelection()
        editingRecipeID = recipes.recipes.first?.id
    }

    // MARK: Settings

    var cli: FujiCLI? {
        FujiCLI.locate(preferredPath: UserDefaults.standard.string(forKey: SettingsKey.fujicliPath))
    }

    var outputFolder: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: SettingsKey.outputFolderPath), !path.isEmpty {
                return URL(filePath: path, directoryHint: .isDirectory)
            }
            return URL.picturesDirectory.appending(path: "Nimble Fuji", directoryHint: .isDirectory)
        }
        set {
            UserDefaults.standard.set(newValue.path(percentEncoded: false), forKey: SettingsKey.outputFolderPath)
            outputFolderRevision += 1
        }
    }
    /// Bumped so views reading `outputFolder` refresh.
    private(set) var outputFolderRevision = 0

    // MARK: Batch

    var batchRecipes: [Recipe] {
        recipes.recipes.filter { batchRecipeIDs.contains($0.id) }
    }

    var batchRaws: [RawFile] {
        library.files.filter { selectedRawIDs.contains($0.id) }
    }

    var renderCount: Int { batchRecipes.count * batchRaws.count }

    var canRender: Bool {
        renderCount > 0 && !renderer.isRunning && batchRecipes.allSatisfy(\.isValid)
    }

    func refreshCamera() {
        camera.refresh(using: cli)
    }

    func startRender() {
        guard let cli else {
            alert = AlertInfo(title: "fujicli not found",
                              message: "Install fujicli or set its location in Settings (⌘,).")
            return
        }
        let invalid = batchRecipes.filter { !$0.isValid }
        if let first = invalid.first {
            alert = AlertInfo(title: "“\(first.name)” has problems",
                              message: first.validationIssues().joined(separator: "\n"))
            return
        }
        let defaults = UserDefaults.standard
        renderer.start(
            raws: batchRaws,
            recipes: batchRecipes,
            outputFolder: outputFolder,
            cli: cli,
            draft: defaults.bool(forKey: SettingsKey.draftRenders),
            overwrite: defaults.bool(forKey: SettingsKey.overwriteExisting))
        showRenderSheet = true
    }

    // MARK: Recipe actions

    func newRecipe() {
        perform {
            let recipe = try recipes.create()
            editingRecipeID = recipe.id
        }
    }

    func duplicate(_ recipe: Recipe) {
        perform {
            let copy = try recipes.duplicate(recipe)
            editingRecipeID = copy.id
        }
    }

    func delete(_ recipe: Recipe) {
        perform {
            try recipes.delete(recipe)
            batchRecipeIDs.remove(recipe.id)
            if editingRecipeID == recipe.id { editingRecipeID = recipes.recipes.first?.id }
        }
    }

    func save(_ recipe: Recipe) {
        perform { try recipes.save(recipe) }
        persistBatchSelection()
    }

    func importRecipes(_ urls: [URL]) {
        let errors = recipes.importFiles(urls)
        if !errors.isEmpty {
            alert = AlertInfo(title: "Some recipes couldn't be imported", message: errors.joined(separator: "\n\n"))
        }
    }

    func reloadRecipes() {
        recipes.reload()
        restoreBatchSelection()
        if recipes.recipe(withID: editingRecipeID) == nil { editingRecipeID = recipes.recipes.first?.id }
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch {
            alert = AlertInfo(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // Batch selection is remembered by file name, since IDs are per-launch.
    private func persistBatchSelection() {
        let names = batchRecipeIDs.compactMap { id in
            recipes.recipe(withID: id).flatMap { recipes.fileURL(for: $0)?.lastPathComponent }
        }
        UserDefaults.standard.set(names, forKey: SettingsKey.batchRecipeFiles)
    }

    private func restoreBatchSelection() {
        let names = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.batchRecipeFiles) ?? [])
        let ids = recipes.recipes.filter { recipe in
            recipes.fileURL(for: recipe).map { names.contains($0.lastPathComponent) } ?? false
        }.map(\.id)
        if Set(ids) != batchRecipeIDs { batchRecipeIDs = Set(ids) }
    }
}
