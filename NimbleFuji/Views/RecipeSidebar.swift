import SwiftUI
import UniformTypeIdentifiers

/// Left pane: a fixed Recipes header, the scrolling recipe list, and a fixed
/// Camera panel at the bottom showing the C slots like the camera's own menu.
struct RecipeSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var pendingDelete: Recipe?
    @State private var choosingBackup = false
    @State private var pendingRestore: URL?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            recipesHeader
            List(selection: $model.editingRecipeID) {
                ForEach(model.recipes.recipes) { recipe in
                    RecipeRow(recipe: recipe, isIncluded: binding(for: recipe))
                        .tag(recipe.id)
                        .draggable(recipe.id.uuidString) {
                            Label(recipe.name, systemImage: "camera.filters")
                                .padding(6)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .contextMenu { menu(for: recipe) }
                }

                if !model.recipes.problems.isEmpty {
                    Section("Couldn't Read") {
                        ForEach(model.recipes.problems) { problem in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(problem.file.lastPathComponent)
                                    Text(problem.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            }
                            .contextMenu {
                                Button("Show in Finder") { model.reveal([problem.file]) }
                            }
                        }
                    }
                }
            }
            .overlay {
                if model.recipes.recipes.isEmpty && model.recipes.problems.isEmpty {
                    ContentUnavailableView {
                        Label("No Recipes", systemImage: "camera.filters")
                    } description: {
                        Text("Create a recipe or import YAML files.")
                    } actions: {
                        Button("New Recipe") { model.newRecipe() }
                    }
                }
            }

            CameraPanel(choosingBackup: $choosingBackup)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "yaml") ?? .plainText,
                                            UTType(filenameExtension: "yml") ?? .plainText],
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { model.importRecipes(urls) }
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [UTType(filenameExtension: "bak") ?? .data, .data]) { result in
            if case let .success(url) = result { pendingRestore = url }
        }
        .confirmationDialog("Move “\(pendingDelete?.name ?? "")” to the Trash?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { recipe in
            Button("Move to Trash", role: .destructive) { model.delete(recipe) }
        } message: { _ in
            Text("The YAML file goes to the Trash, so you can still restore it.")
        }
        .confirmationDialog("Restore all camera settings from “\(pendingRestore?.lastPathComponent ?? "")”?",
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            presenting: pendingRestore) { url in
            Button("Restore", role: .destructive) { model.restoreCamera(from: url) }
        } message: { _ in
            Text("This replaces every C slot and the camera's menu settings with the backup's.")
        }
    }

    // MARK: Recipes header (always visible)

    private var recipesHeader: some View {
        HStack(spacing: 6) {
            Text("Recipes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(model.batchRecipeIDs.count) of \(model.recipes.recipes.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .help("Recipes ticked for the next render")
            Spacer(minLength: 4)
            if !model.recipes.recipes.isEmpty {
                Button(allIncluded ? "None" : "All") {
                    model.batchRecipeIDs = allIncluded ? [] : Set(model.recipes.recipes.map(\.id))
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            Button { model.newRecipe() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("New recipe")
            Menu {
                Button("Import YAML Files…") { importing = true }
                Button("Show Recipes Folder") { model.reveal([model.recipes.folder]) }
                Button("Reload Recipes") { model.reloadRecipes() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var allIncluded: Bool {
        !model.recipes.recipes.isEmpty && model.batchRecipeIDs.count == model.recipes.recipes.count
    }

    private func binding(for recipe: Recipe) -> Binding<Bool> {
        Binding {
            model.batchRecipeIDs.contains(recipe.id)
        } set: { included in
            if included { model.batchRecipeIDs.insert(recipe.id) } else { model.batchRecipeIDs.remove(recipe.id) }
        }
    }

    @ViewBuilder
    private func menu(for recipe: Recipe) -> some View {
        let slotsReady = model.slotsAvailable
        ForEach(model.slots.slots) { slot in
            Button(slot.name.isEmpty ? "Assign to \(slot.title)" : "Assign to \(slot.title)  (\(slot.name))") {
                model.requestSlotWrite(recipeID: recipe.id, slot: slot.number)
            }
            .disabled(!slotsReady)
        }
        if !slotsReady {
            Text(model.camera.status.isConnected ? "Reading camera slots…" : "Connect the camera to assign slots")
        }
        Divider()
        Button("Duplicate") { model.duplicate(recipe) }
        if let url = model.recipes.fileURL(for: recipe) {
            Button("Show in Finder") { model.reveal([url]) }
        }
        Divider()
        Button("Move to Trash…", role: .destructive) { pendingDelete = recipe }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    @Binding var isIncluded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Include in batch", isOn: $isIncluded)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Include this recipe in the next render")
            VStack(alignment: .leading, spacing: 1) {
                Text(recipe.name)
                    .lineLimit(1)
                Text(recipe.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !recipe.isValid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(recipe.validationIssues().joined(separator: "\n"))
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Camera panel (always visible)

/// The camera's C slots, drawn like the X-T5's EDIT/SAVE CUSTOM SETTING menu:
/// white text on black, with an inverted C1…C7 badge.
private struct CameraPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var choosingBackup: Bool
    @State private var namingSlot: CameraSlots.Slot?
    @State private var newRecipeName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            header
            slotsScreen
        }
        .padding(.bottom, 10)
        .alert("Save \(namingSlot?.title ?? "") as Recipe",
               isPresented: Binding(get: { namingSlot != nil }, set: { if !$0 { namingSlot = nil } })) {
            TextField("Recipe name", text: $newRecipeName)
            Button("Save") {
                if let slot = namingSlot { model.saveSlotAsRecipe(slot, name: newRecipeName) }
                namingSlot = nil
            }
            .disabled(newRecipeName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { namingSlot = nil }
        } message: {
            Text("The slot's settings are saved as a new YAML recipe.")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Camera")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let message = model.slots.busyMessage ?? (model.slots.isLoading ? "Reading slots…" : nil) {
                ProgressView().controlSize(.mini).help(message)
            }
            Spacer()
            Button { model.loadSlots() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read the C slots from the camera")
                .disabled(!model.canUseSlots || !model.camera.status.isConnected)
            Menu {
                Button("Back Up Camera Now") { model.backUpCamera() }
                Button("Restore Backup…") { choosingBackup = true }
                Divider()
                Button("Show Backups Folder") {
                    try? FileManager.default.createDirectory(at: CameraSlots.backupFolder, withIntermediateDirectories: true)
                    model.reveal([CameraSlots.backupFolder])
                }
            } label: {
                Image(systemName: "externaldrive.badge.timemachine")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Camera backups")
            .disabled(!model.canUseSlots || !model.camera.status.isConnected)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var slotsScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !model.camera.status.isConnected && !model.slots.hasLoaded {
                Text("Connect the camera in USB RAW CONV. mode to see its C slots.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(8)
            } else if let error = model.slots.lastError, model.slots.slots.allSatisfy({ $0.recipe == nil }) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(4)
                    .padding(8)
            } else {
                ForEach(model.slots.slots) { slot in
                    SlotRow(slot: slot)
                        .contextMenu {
                            Button("Save as Recipe…") {
                                newRecipeName = slot.name.isEmpty ? "\(slot.title) Recipe" : slot.name
                                namingSlot = slot
                            }
                            .disabled(slot.recipe == nil)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 10)
    }
}

private struct SlotRow: View {
    @Environment(AppModel.self) private var model
    let slot: CameraSlots.Slot
    @State private var isTargeted = false
    @State private var showDetails = false

    var body: some View {
        HStack(spacing: 7) {
            // Red bar like the camera's selection marker, shown while a recipe is dragged over.
            Rectangle()
                .fill(isTargeted ? Color.red : .clear)
                .frame(width: 3)
            Text(slot.title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 2.5))
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(slot.recipe == nil || slot.name.isEmpty ? Color.white.opacity(0.45) : .white)
                .lineLimit(1)
            Spacer(minLength: 0)
            if slot.isWriting {
                ProgressView().controlSize(.mini).tint(.white)
            } else if slot.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
            }
        }
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(isTargeted ? Color.white.opacity(0.12) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { if slot.recipe != nil { showDetails = true } }
        .popover(isPresented: $showDetails, arrowEdge: .trailing) { SlotDetails(slot: slot) }
        .help(help)
        .dropDestination(for: String.self) { items, _ in
            guard model.slotsAvailable, let first = items.first, let id = UUID(uuidString: first) else { return false }
            model.requestSlotWrite(recipeID: id, slot: slot.number)
            return true
        } isTargeted: { isTargeted = $0 && model.slotsAvailable }
    }

    private var title: String {
        guard slot.recipe != nil else { return model.slots.isLoading ? "…" : "—" }
        return slot.name.isEmpty ? "CUSTOM \(slot.number)" : slot.name
    }

    private var help: String {
        if let error = slot.error { return error }
        let summary = slot.recipe?.summary ?? ""
        return "\(summary)\nClick for settings, right-click to save as a recipe, or drop a recipe here to write it."
    }
}
