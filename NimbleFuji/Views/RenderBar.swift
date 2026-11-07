import SwiftUI

/// Bottom bar: output folder, batch size, and the Render button.
struct RenderBar: View {
    @Environment(AppModel.self) private var model
    @State private var choosingFolder = false

    var body: some View {
        let _ = model.outputFolderRevision
        HStack(spacing: 12) {
            Button {
                choosingFolder = true
            } label: {
                Label(model.outputFolder.lastPathComponent, systemImage: "folder")
            }
            .help("Output folder: \(model.outputFolder.path(percentEncoded: false))")
            .contextMenu {
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: model.outputFolder, withIntermediateDirectories: true)
                    model.reveal([model.outputFolder])
                }
            }

            Text(summary)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            if !model.renderer.jobs.isEmpty && !model.showRenderSheet {
                Button("Last Batch") { model.showRenderSheet = true }
            }

            Button {
                model.startRender()
            } label: {
                Label(model.renderer.isRunning ? "Rendering…" : "Render", systemImage: "camera.aperture")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canRender)
            .help(helpText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { model.outputFolder = url }
        }
    }

    private var summary: String {
        let recipes = model.batchRecipes.count, raws = model.batchRaws.count
        let r = recipes == 1 ? "1 recipe" : "\(recipes) recipes"
        let f = raws == 1 ? "1 RAW" : "\(raws) RAWs"
        let total = model.renderCount == 1 ? "1 JPG" : "\(model.renderCount) JPGs"
        return "\(r) × \(f) = \(total)"
    }

    private var helpText: String {
        if model.batchRecipes.isEmpty { return "Tick at least one recipe in the sidebar." }
        if model.batchRaws.isEmpty { return "Select at least one RAW file." }
        if let bad = model.batchRecipes.first(where: { !$0.isValid }) { return "Fix “\(bad.name)” first." }
        return "Render on the camera and save the JPGs to \(model.outputFolder.lastPathComponent)."
    }
}
