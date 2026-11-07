import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.fujicliPath) private var fujicliPath = ""
    @AppStorage(SettingsKey.overwriteExisting) private var overwriteExisting = false
    @AppStorage(SettingsKey.draftRenders) private var draftRenders = false
    @State private var choosingTool = false
    @State private var choosingRecipeFolder = false
    @State private var releaseMessage: String?

    var body: some View {
        Form {
            Section("fujicli") {
                LabeledContent("Location") {
                    HStack {
                        TextField("Location", text: $fujicliPath, prompt: Text(detectedPath ?? "Not found"))
                            .labelsHidden()
                        Button("Choose…") { choosingTool = true }
                    }
                }
                LabeledContent("Status") {
                    if let detectedPath {
                        Text(model.camera.toolVersion.map { "\($0) at \(detectedPath)" } ?? detectedPath)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Not found. Build it from github.com/karaolidis/fujicli and set its location.")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Rendering") {
                Toggle("Overwrite existing JPGs", isOn: $overwriteExisting)
                Text("When off, new files get a -2, -3… suffix instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Draft quality (faster previews)", isOn: $draftRenders)
            }

            Section("Recipes") {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.recipes.folder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                        Button("Change…") { choosingRecipeFolder = true }
                        Button("Show") { model.reveal([model.recipes.folder]) }
                    }
                }
            }

            Section {
                Button("Release Camera from macOS") { releaseCamera() }
                if let releaseMessage {
                    Text(releaseMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Troubleshooting")
            } footer: {
                Text("Quits macOS's ptpcamerad, which can grab the camera when it's plugged in. macOS restarts it on demand.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingTool, allowedContentTypes: [.unixExecutable, .item]) { result in
            if case let .success(url) = result {
                fujicliPath = url.path(percentEncoded: false)
                model.refreshCamera()
            }
        }
        .fileImporter(isPresented: $choosingRecipeFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                model.recipes.changeFolder(to: url)
                model.reloadRecipes()
            }
        }
        .onChange(of: fujicliPath) { model.refreshCamera() }
    }

    private var detectedPath: String? {
        _ = fujicliPath
        return model.cli?.executable.path(percentEncoded: false)
    }

    private func releaseCamera() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/killall")
        process.arguments = ["ptpcamerad"]
        do {
            try process.run()
            process.waitUntilExit()
            releaseMessage = process.terminationStatus == 0
                ? "Done. Reconnect the camera, then check again."
                : "ptpcamerad wasn't running."
        } catch {
            releaseMessage = error.localizedDescription
        }
        model.refreshCamera()
    }
}
