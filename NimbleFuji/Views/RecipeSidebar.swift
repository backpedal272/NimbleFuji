import SwiftUI
import UniformTypeIdentifiers

struct RecipeSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var pendingDelete: Recipe?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.editingRecipeID) {
            Section {
                ForEach(model.recipes.recipes) { recipe in
                    RecipeRow(recipe: recipe, isIncluded: binding(for: recipe),
                              showsCheckbox: model.workspace == .render)
                        .tag(recipe.id)
                        .draggable(recipe.id.uuidString) {
                            Label(recipe.name, systemImage: "camera.filters")
                                .padding(6)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .contextMenu { menu(for: recipe) }
                }
            } header: {
                HStack {
                    Text("Recipes")
                    Spacer()
                    if !model.recipes.recipes.isEmpty {
                        Button(allIncluded ? "None" : "All") {
                            model.batchRecipeIDs = allIncluded ? [] : Set(model.recipes.recipes.map(\.id))
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
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
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Button { model.newRecipe() } label: { Image(systemName: "plus") }
                    .help("New recipe")
                Menu {
                    Button("Import YAML Files…") { importing = true }
                    Button("Show Recipes Folder") { model.reveal([model.recipes.folder]) }
                    Button("Reload Recipes") { model.reloadRecipes() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
                Text("\(model.batchRecipeIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "yaml") ?? .plainText,
                                            UTType(filenameExtension: "yml") ?? .plainText],
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { model.importRecipes(urls) }
        }
        .confirmationDialog("Move “\(pendingDelete?.name ?? "")” to the Trash?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { recipe in
            Button("Move to Trash", role: .destructive) { model.delete(recipe) }
        } message: { _ in
            Text("The YAML file goes to the Trash, so you can still restore it.")
        }
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
    var showsCheckbox = true

    var body: some View {
        HStack(spacing: 8) {
            if showsCheckbox {
                Toggle("Include in batch", isOn: $isIncluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Include this recipe in the next render")
            }
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 2)
    }
}
