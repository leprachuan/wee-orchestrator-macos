import SwiftUI

@main
struct WeeOrchestratorApp: App {
    @State private var model = WeeAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    Task { await model.startNewChat() }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh All") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
