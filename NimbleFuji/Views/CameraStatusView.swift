import SwiftUI

struct CameraStatusView: View {
    @Environment(AppModel.self) private var model
    @State private var showHelp = false

    var body: some View {
        Button {
            showHelp.toggle()
        } label: {
            HStack(spacing: 6) {
                indicator
                Text(title).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .help("Camera connection")
        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
            CameraHelp()
                .environment(model)
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.camera.status {
        case .checking:
            ProgressView().controlSize(.mini)
        case .connected:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .notConnected, .unknown:
            Circle().fill(.secondary).frame(width: 8, height: 8)
        case .toolMissing, .error:
            Circle().fill(.orange).frame(width: 8, height: 8)
        }
    }

    private var title: String {
        switch model.camera.status {
        case .unknown: "Camera"
        case .checking: "Checking…"
        case let .connected(name): name
        case .notConnected: "No Camera"
        case .toolMissing: "fujicli Missing"
        case .error: "Camera Error"
        }
    }
}

private struct CameraHelp: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.camera.status {
            case let .connected(name):
                Label("\(name) is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .error(message):
                Label("fujicli reported an error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message).font(.caption).textSelection(.enabled)
            case .toolMissing:
                Label("fujicli isn't installed or can't be found.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                SettingsLink { Text("Open Settings…") }
            default:
                Label("No camera found", systemImage: "camera")
            }

            Divider()
            Text("To render on the X-T5").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Connect with a USB data cable (charge-only cables don't work).")
                step(2, "MENU › NETWORK/USB SETTING › CONNECTION MODE › USB RAW CONV./BACKUP RESTORE.")
                step(3, "Set USB POWER SUPPLY/COMM SETTING to AUTO.")
                step(4, "Turn off AUTO POWER OFF so the camera stays awake during long batches.")
            }
            .font(.callout)

            HStack {
                if let version = model.camera.toolVersion {
                    Text(version).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Again") { model.refreshCamera() }
                    .disabled(model.renderer.isRunning)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
