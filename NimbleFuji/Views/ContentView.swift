import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showEditor = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            RecipeSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            RawFilesView()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    RenderBar()
                }
        }
        .inspector(isPresented: $showEditor) {
            RecipeInspector()
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                CameraStatusView()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor.toggle()
                } label: {
                    Label("Recipe Editor", systemImage: "slider.horizontal.3")
                }
                .help("Show or hide the recipe editor")
            }
        }
        .sheet(isPresented: $model.showRenderSheet) {
            RenderProgressView()
        }
        .sheet(item: $model.pendingSlotWrite) { write in
            SlotWriteSheet(write: write)
        }
        .onChange(of: model.camera.status) { model.cameraStatusChanged() }
        .alert(item: $model.alert) { info in
            Alert(title: Text(info.title), message: Text(info.message))
        }
        .onAppear {
            // Let the window finish appearing, then ask before touching the camera.
            DispatchQueue.main.async {
                let window = NSApp.windows.first { $0.identifier?.rawValue == "main" }
                    ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
                Disclaimer.confirmOrQuit(in: window) {
                    model.refreshCamera()
                    #if DEBUG
                    DebugSnapshot.scheduleIfRequested()
                    #endif
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if Disclaimer.isAccepted && !model.renderer.isRunning { model.refreshCamera() }
        }
    }
}
