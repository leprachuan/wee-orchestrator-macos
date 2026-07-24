import SwiftUI

/// Testability seam for issue #7 — lets tests verify applicationWillTerminate
/// calls stopLocalAPI() without spinning up a real WeeAppModel/subprocess.
@MainActor
protocol LocalServiceStoppable: AnyObject {
    func stopLocalAPIForApplicationTermination()
}

extension WeeAppModel: LocalServiceStoppable {}

/// Issue #7: nothing terminated the local API subprocess (`agent_manager.py
/// --api`) when the app quit, leaving it running as an orphan bound to port
/// 8001 — a stale process a fresh launch had no way to detect or replace.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: LocalServiceStoppable?

    /// An app replacement can only move the running bundle after this process
    /// exits.  Returning `.terminateNow` prevents an open sheet or window
    /// delegate from leaving the updater parked at "Installing…" forever.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stopLocalAPIForApplicationTermination()
    }
}

@main
struct WeeOrchestratorApp: App {
    @State private var model = WeeAppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .dynamicTypeSize(model.appTextSize)
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

                Divider()

                Button("Check for Updates…") {
                    Task { await model.checkForAppUpdate(showResult: true) }
                }

                Button("Install Available Update") {
                    Task { await model.installAvailableAppUpdate() }
                }
                .disabled(model.availableAppUpdate == nil || model.isInstallingAppUpdate)
            }
        }
    }
}
