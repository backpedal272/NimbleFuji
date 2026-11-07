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
            switch model.workspace {
            case .render:
                RawFilesView()
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        RenderBar()
                    }
            case .slots:
                CameraSlotsView()
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
            ToolbarItem(placement: .principal) {
                Picker("Workspace", selection: $model.workspace) {
                    ForEach(AppModel.Workspace.allCases) { space in
                        Label(space.rawValue, systemImage: space.systemImage).tag(space)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .help("Switch between rendering RAWs and managing the camera's C slots")
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
        .alert(item: $model.alert) { info in
            Alert(title: Text(info.title), message: Text(info.message))
        }
        .onAppear { model.refreshCamera() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !model.renderer.isRunning { model.refreshCamera() }
        }
    }
}
