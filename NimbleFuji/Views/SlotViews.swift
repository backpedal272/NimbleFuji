import SwiftUI

struct SlotDetails: View {
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
