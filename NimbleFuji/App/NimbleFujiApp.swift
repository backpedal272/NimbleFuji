import SwiftUI

@main
struct NimbleFujiApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Nimble Fuji", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Recipe") { model.newRecipe() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Render") {
                Button("Render Selection") { model.startRender() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.canRender)
                Button("Check Camera") { model.refreshCamera() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
