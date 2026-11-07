import SwiftUI
import UniformTypeIdentifiers

/// Shows the camera's C1–C7 slots. Drag a recipe from the sidebar onto a slot to write it.
struct CameraSlotsView: View {
    @Environment(AppModel.self) private var model
    @State private var choosingBackup = false
    @State private var pendingRestore: URL?

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 14)]

    var body: some View {
        let slots = model.slots
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let error = slots.lastError, slots.slots.allSatisfy({ $0.recipe == nil }) {
                    ContentUnavailableView {
                        Label("Couldn't Read the Camera", systemImage: "camera.badge.ellipsis")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { model.loadSlots() }
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(slots.slots) { slot in
                            SlotCard(slot: slot)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Camera Slots")
        .navigationSubtitle(model.camera.status.isConnected ? "Drag a recipe onto a slot to write it" : "No camera connected")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.loadSlots() } label: {
                    Label("Read Camera", systemImage: "arrow.clockwise")
                }
                .help("Read all slots from the camera")
                .disabled(!model.canUseSlots)
                Menu {
                    Button("Back Up Camera Now") { model.backUpCamera() }
                    Button("Restore Backup…") { choosingBackup = true }
                    Divider()
                    Button("Show Backups Folder") {
                        try? FileManager.default.createDirectory(at: CameraSlots.backupFolder, withIntermediateDirectories: true)
                        model.reveal([CameraSlots.backupFolder])
                    }
                } label: {
                    Label("Backups", systemImage: "externaldrive.badge.timemachine")
                }
                .disabled(!model.canUseSlots)
            }
        }
        .task {
            if !model.slots.hasLoaded, model.canUseSlots { model.loadSlots() }
        }
        .sheet(item: Binding(get: { model.pendingSlotWrite }, set: { model.pendingSlotWrite = $0 })) { write in
            SlotWriteSheet(write: write)
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [UTType(filenameExtension: "bak") ?? .data, .data]) { result in
            if case let .success(url) = result { pendingRestore = url }
        }
        .confirmationDialog("Restore all camera settings from “\(pendingRestore?.lastPathComponent ?? "")”?",
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            presenting: pendingRestore) { url in
            Button("Restore", role: .destructive) { model.restoreCamera(from: url) }
        } message: { _ in
            Text("This replaces every C slot and the camera's menu settings with the backup's.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let message = model.slots.busyMessage ?? (model.slots.isLoading ? "Reading slots…" : nil) {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            } else if let backup = model.slots.sessionBackup {
                Image(systemName: "checkmark.shield").foregroundStyle(.green)
                Text("Backed up as \(backup.lastPathComponent)")
                    .foregroundStyle(.secondary)
                    .onTapGesture { model.reveal([backup]) }
            } else {
                Image(systemName: "shield").foregroundStyle(.secondary)
                Text("The camera is backed up automatically before the first write.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
    }
}

private struct SlotCard: View {
    @Environment(AppModel.self) private var model
    let slot: CameraSlots.Slot
    @State private var isTargeted = false
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(slot.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(slot.name.isEmpty ? .secondary : .primary)
                Spacer(minLength: 0)
                if slot.isWriting { ProgressView().controlSize(.small) }
                menu
            }

            if let recipe = slot.recipe {
                Text(recipe.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    ForEach(Array(recipe.settingRows.dropFirst().prefix(6).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label).foregroundStyle(.secondary)
                            Text(row.value).monospacedDigit()
                        }
                    }
                }
                .font(.caption)
            } else if let error = slot.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(4)
            } else {
                Text(model.slots.isLoading ? "Reading…" : "Not read yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isTargeted ? 3 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 2) { if slot.recipe != nil { showDetails = true } }
        .popover(isPresented: $showDetails) { SlotDetails(slot: slot) }
        .dropDestination(for: String.self) { items, _ in
            guard model.canUseSlots, let first = items.first, let id = UUID(uuidString: first) else { return false }
            model.requestSlotWrite(recipeID: id, slot: slot.number)
            return true
        } isTargeted: { isTargeted = $0 && model.canUseSlots }
    }

    private var displayName: String {
        if slot.recipe == nil { return "—" }
        return slot.name.isEmpty ? "Unnamed" : slot.name
    }

    private var menu: some View {
        Menu {
            Menu("Write Recipe") {
                ForEach(model.recipes.recipes) { recipe in
                    Button(recipe.name) { model.requestSlotWrite(recipeID: recipe.id, slot: slot.number) }
                }
            }
            .disabled(!model.canUseSlots || model.recipes.recipes.isEmpty)
            Button("Save as Recipe") { model.saveSlotAsRecipe(slot) }
                .disabled(slot.recipe == nil)
            Button("Show All Settings") { showDetails = true }
                .disabled(slot.recipe == nil)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct SlotDetails: View {
    let slot: CameraSlots.Slot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(slot.title) · \(slot.name.isEmpty ? "Unnamed" : slot.name)").font(.headline)
            if let recipe = slot.recipe {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(Array(recipe.settingRows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label).foregroundStyle(.secondary)
                            Text(row.value).monospacedDigit()
                        }
                    }
                }
                .font(.callout)
            }
        }
        .padding(16)
    }
}

/// Confirms a slot write and shows what will change.
struct SlotWriteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let write: AppModel.SlotWrite

    var body: some View {
        let current = model.slots.slots[write.slot - 1].recipe
        let incoming = write.recipe.forSlot()
        let newName = Recipe.slotName(for: write.recipe.name)
        let before = current?.settingRows ?? []
        let after = incoming.settingRows

        VStack(alignment: .leading, spacing: 14) {
            Text("Write “\(write.recipe.name)” to C\(write.slot)?")
                .font(.title3.bold())
            Text("This replaces \(current.map { $0.name.isEmpty ? "the unnamed recipe" : "“\($0.name)”" } ?? "whatever is") in C\(write.slot) on the camera.")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Setting").bold()
                    Text("Now").bold()
                    Text("After").bold()
                }
                Divider()
                row("Name", current?.name ?? "—", newName)
                ForEach(Array(after.enumerated()), id: \.offset) { index, item in
                    let old = before.first { $0.label == item.label }?.value ?? "—"
                    row(item.label, old, item.value)
                }
            }
            .font(.callout)
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                if newName != write.recipe.name {
                    Label("The camera allows 25 plain characters, so the name is shortened to “\(newName)”.", systemImage: "textformat")
                }
                Label("Settings the recipe leaves at “As shot” are reset to neutral. Image size, quality and color space stay as they are.", systemImage: "info.circle")
                if model.slots.sessionBackup == nil {
                    Label("The camera's settings are backed up first.", systemImage: "externaldrive.badge.checkmark")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Write to C\(write.slot)") { model.performSlotWrite(write) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    @ViewBuilder
    private func row(_ label: String, _ old: String, _ new: String) -> some View {
        let changed = old != new
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(old).foregroundStyle(changed ? .secondary : .primary).strikethrough(changed && old != "—")
            Text(new).fontWeight(changed ? .semibold : .regular).foregroundStyle(changed ? Color.accentColor : .primary)
        }
    }
}
