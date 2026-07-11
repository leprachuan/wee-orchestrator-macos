import SwiftUI

/// Testability seam for issue #7 — lets tests verify applicationWillTerminate
/// calls stopLocalAPI() without spinning up a real WeeAppModel/subprocess.
protocol LocalServiceStoppable: AnyObject {
    func stopLocalAPI()
}

extension WeeAppModel: LocalServiceStoppable {}

/// Issue #7: nothing terminated the local API subprocess (`agent_manager.py
/// --api`) when the app quit, leaving it running as an orphan bound to port
/// 8001 — a stale process a fresh launch had no way to detect or replace.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: LocalServiceStoppable?

    func applicationWillTerminate(_ notification: Notification) {
        model?.stopLocalAPI()
    }
}

@main
struct WeeOrchestratorApp: App {
    @State private var model = WeeAppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Keep WindowGroup's standard New Window command. Replacing the
            // group removed it, which made this otherwise multi-window scene
            // behave like a single-window app.
            CommandGroup(after: .newItem) {
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
