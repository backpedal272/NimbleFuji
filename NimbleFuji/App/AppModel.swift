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
    let slots = CameraSlots()

    enum Workspace: String, CaseIterable, Identifiable {
        case render = "Render"
        case slots = "Camera Slots"
        var id: String { rawValue }
        var systemImage: String { self == .render ? "photo.stack" : "square.grid.3x3" }
    }

    var workspace: Workspace = .render
    /// A pending slot write waiting for the user's confirmation.
    var pendingSlotWrite: SlotWrite?

    struct SlotWrite: Identifiable {
        let id = UUID()
        let recipe: Recipe
        let slot: Int
    }

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
        renderCount > 0 && !renderer.isRunning && !slots.isBusy && batchRecipes.allSatisfy(\.isValid)
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

    // MARK: Camera slots

    var canUseSlots: Bool { !renderer.isRunning && !slots.isBusy }

    func loadSlots() {
        guard let cli else {
            alert = AlertInfo(title: "fujicli not found", message: "Set its location in Settings (⌘,).")
            return
        }
        Task { await slots.load(using: cli) }
    }

    /// Asks for confirmation before writing; see `SlotWriteSheet`.
    func requestSlotWrite(recipeID: Recipe.ID, slot: Int) {
        guard let recipe = recipes.recipe(withID: recipeID) else { return }
        guard recipe.isValid else {
            alert = AlertInfo(title: "“\(recipe.name)” has problems",
                              message: recipe.validationIssues().joined(separator: "\n"))
            return
        }
        pendingSlotWrite = SlotWrite(recipe: recipe, slot: slot)
    }

    func performSlotWrite(_ write: SlotWrite) {
        guard let cli else { return }
        pendingSlotWrite = nil
        Task {
            do {
                try await slots.write(write.recipe, to: write.slot, using: cli)
            } catch {
                alert = AlertInfo(title: "Couldn't write C\(write.slot)", message: error.localizedDescription)
            }
        }
    }

    func backUpCamera() {
        guard let cli else { return }
        Task {
            do {
                let url = try await slots.backUpNow(using: cli)
                reveal([url])
            } catch {
                alert = AlertInfo(title: "Backup failed", message: error.localizedDescription)
            }
        }
    }

    func restoreCamera(from url: URL) {
        guard let cli else { return }
        Task {
            do {
                try await slots.restore(from: url, using: cli)
            } catch {
                alert = AlertInfo(title: "Restore failed", message: error.localizedDescription)
            }
        }
    }

    /// Saves a slot's settings as a new YAML recipe.
    func saveSlotAsRecipe(_ slot: CameraSlots.Slot) {
        guard var recipe = slot.recipe else { return }
        recipe.id = UUID()
        let base = recipe.name.trimmingCharacters(in: .whitespaces)
        recipe.name = recipes.uniqueName(base.isEmpty ? "C\(slot.number) Recipe" : base)
        recipe.source = "X-T5 custom slot C\(slot.number)"
        perform {
            let saved = try recipes.save(recipe)
            editingRecipeID = saved.id
        }
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
