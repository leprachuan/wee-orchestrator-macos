import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case chat, kanban, backgroundTasks, scheduledTasks, agents, localModels, remoteSettings, localSettings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .kanban: "Kanban"
        case .backgroundTasks: "Background Tasks"
        case .scheduledTasks: "Scheduled Tasks"
        case .agents: "Agents"
        case .localModels: "Local Models"
        case .remoteSettings: "Remote Settings"
        case .localSettings: "Local Settings"
        }
    }

    var eyebrow: String {
        switch self {
        case .chat: "CONVERSE"
        case .kanban: "PLAN"
        case .backgroundTasks: "EXECUTE"
        case .scheduledTasks: "AUTOMATE"
        case .agents: "TEAM"
        case .localModels: "ON DEVICE"
        case .remoteSettings: "REMOTE"
        case .localSettings: "LOCAL"
        }
    }

    var symbol: String {
        switch self {
        case .chat: "bubble.left.and.text.bubble.right.fill"
        case .kanban: "rectangle.3.group.fill"
        case .backgroundTasks: "bolt.fill"
        case .scheduledTasks: "calendar.badge.clock"
        case .agents: "person.2.fill"
        case .localModels: "cpu"
        case .remoteSettings: "network"
        case .localSettings: "desktopcomputer"
        }
    }
}

struct ContentView: View {
    @Bindable var model: WeeAppModel
    @State private var selectedSection: AppSection = .chat
    /// Issue #22: the Local/Remote environment previously lived only on the
    /// shared model, so it was effectively one global toggle for every open
    /// window. `WeeAppModel` is a single instance shared across all windows
    /// (native multi-window support), so this per-window @State is what
    /// gives each window its own remembered mode — SwiftUI allocates
    /// independent @State storage per window/view-identity. New windows
    /// default to Local, matching the issue's stated default.
    @State private var windowEnvironment: WeeEnvironment = .local
    @State private var thisWindow: NSWindow?
    @State private var browserStore = BrowserSessionStore()

    var body: some View {
        HStack(spacing: 0) {
            workspaceRail

            ZStack {
                WeeBackground()
                sectionView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WindowAccessor(window: $thisWindow))
        .background(WeeTheme.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1180, minHeight: 680)
        .task {
            await model.bootstrap()
            if model.activeEnvironment != windowEnvironment {
                await model.switchEnvironment(to: windowEnvironment)
            }
        }
        .onChange(of: model.kanbanEnabled) { _, enabled in
            if !enabled, selectedSection == .kanban {
                selectedSection = .chat
            }
        }
        .onChange(of: model.activeEnvironment) { _, newValue in
            // Only adopt the change if it happened while this window was the
            // one the user was driving — otherwise another window switching
            // its own mode would silently overwrite this window's memory too.
            guard thisWindow?.isKeyWindow == true else { return }
            windowEnvironment = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, window === thisWindow else { return }
            guard model.activeEnvironment != windowEnvironment else { return }
            Task { await model.switchEnvironment(to: windowEnvironment) }
        }
        .sheet(isPresented: isUpdateModalPresented) {
            if let update = model.availableAppUpdate {
                AppUpdateModal(model: model, update: update)
            }
        }
        .interactiveDismissDisabled(model.isInstallingAppUpdate)
    }

    private var environmentPicker: some View {
        Menu {
            ForEach(WeeEnvironment.allCases) { environment in
                Button {
                    windowEnvironment = environment
                    Task { await model.switchEnvironment(to: environment) }
                } label: {
                    Label(environment.title, systemImage: environment == model.activeEnvironment ? "checkmark.circle.fill" : environment.symbol)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.activeEnvironment.symbol)
                Text("\(model.activeEnvironment.title) API")
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .weeFont(size: 8, weight: .bold)
                    .foregroundStyle(WeeTheme.textMuted)
                Text(model.agents.count.description)
                    .foregroundStyle(WeeTheme.accent)
            }
            .weeFont(.caption2, weight: .semibold)
            .foregroundStyle(WeeTheme.textSecondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("This window's Local/Remote mode")
    }

    /// Issue #19: an available update now surfaces as a real modal (blocking,
    /// dismissible only via its own buttons while an install isn't running)
    /// instead of a passive overlay banner the user could miss.
    private var isUpdateModalPresented: Binding<Bool> {
        Binding(
            get: { model.availableAppUpdate != nil },
            set: { presented in
                if !presented {
                    model.availableAppUpdate = nil
                    model.appUpdateStatus = nil
                }
            }
        )
    }

    private var visibleSections: [AppSection] {
        AppSection.allCases.filter { $0 != .kanban || model.kanbanEnabled }
    }

    private var workspaceRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image("WeeIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 0) {
                    Text("WEE")
                        .weeFont(size: 14, weight: .black, design: .rounded)
                        .foregroundStyle(WeeTheme.textPrimary)
                    Text("ORCHESTRATOR")
                        .weeFont(size: 8, weight: .bold)
                        .tracking(1.1)
                        .foregroundStyle(WeeTheme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 18)

            Text("WORKSPACE")
                .weeFont(size: 9, weight: .bold)
                .tracking(1.2)
                .foregroundStyle(WeeTheme.textMuted)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            VStack(spacing: 3) {
                ForEach(visibleSections) { section in
                    railButton(section)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(isHealthy ? WeeTheme.emerald : WeeTheme.gold)
                        .frame(width: 7, height: 7)
                        .shadow(color: (isHealthy ? WeeTheme.emerald : WeeTheme.gold).opacity(0.5), radius: 4)
                    Text(isHealthy ? "System online" : "Connection pending")
                        .weeFont(.caption, weight: .semibold)
                        .foregroundStyle(WeeTheme.textPrimary)
                }

                environmentPicker

                HStack {
                    Text(model.health?.environment ?? model.appConfig?.appEnv ?? "Not connected")
                        .weeFont(.caption2)
                        .foregroundStyle(WeeTheme.textMuted)
                        .lineLimit(1)
                    Spacer()
                    if model.isLoading {
                        ProgressView().controlSize(.mini).tint(WeeTheme.accent)
                    }
                }

                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("Refresh data", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    Task { await model.checkForAppUpdate(showResult: true) }
                } label: {
                    Label(
                        model.availableAppUpdate == nil ? "Check for updates" : "Update available",
                        systemImage: model.availableAppUpdate == nil ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(model.isCheckingForAppUpdate || model.isInstallingAppUpdate)
            }
            .padding(10)
            .background(WeeTheme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(WeeTheme.glassStroke))
            .padding(8)
        }
        .frame(width: 196)
        .background(WeeTheme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(WeeTheme.divider).frame(width: 1) }
    }

    private func railButton(_ section: AppSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .weeFont(size: 13, weight: .semibold)
                    .frame(width: 18)
                    .foregroundStyle(selectedSection == section ? WeeTheme.accent : WeeTheme.textSecondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .weeFont(size: 13, weight: .semibold)
                        .foregroundStyle(selectedSection == section ? WeeTheme.textPrimary : WeeTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(section.eyebrow)
                        .weeFont(size: 8, weight: .bold)
                        .tracking(0.7)
                        .foregroundStyle(WeeTheme.textMuted)
                }

                Spacer(minLength: 4)
                if badgeCount(for: section) > 0 {
                    Text("\(badgeCount(for: section))")
                        .weeFont(size: 9, weight: .bold)
                        .foregroundStyle(section == .kanban ? WeeTheme.gold : WeeTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((section == .kanban ? WeeTheme.gold : WeeTheme.accent).opacity(0.13), in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 43)
            .background(selectedSection == section ? WeeTheme.surfaceRaised : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .leading) {
                if selectedSection == section {
                    RoundedRectangle(cornerRadius: 2).fill(WeeTheme.accent).frame(width: 3, height: 22)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var sectionView: some View {
        switch selectedSection {
        case .chat: ChatBrowserWorkspace(model: model, store: browserStore)
        case .kanban:
            if model.kanbanEnabled {
                KanbanView(model: model)
            } else {
                ChatBrowserWorkspace(model: model, store: browserStore)
            }
        case .backgroundTasks: TasksView(model: model, mode: .background)
        case .scheduledTasks: TasksView(model: model, mode: .scheduled)
        case .agents: AgentsView(model: model)
        case .localModels: LocalModelsView(model: model)
        case .remoteSettings: SettingsView(model: model, environment: .remote)
        case .localSettings: SettingsView(model: model, environment: .local)
        }
    }

    private var isHealthy: Bool { model.health?.status == "ok" }
    private var runningCount: Int { model.tasks.filter { $0.status == "running" }.count }
    private var scheduledCount: Int { model.scheduledJobs.filter { $0.enabled != false }.count }
    private var dueCount: Int { model.kanbanBoard?.dueCards.count ?? 0 }

    private func badgeCount(for section: AppSection) -> Int {
        switch section {
        case .kanban: dueCount
        case .backgroundTasks: runningCount
        case .scheduledTasks: scheduledCount
        default: 0
        }
    }
}

private struct AppUpdateModal: View {
    @Bindable var model: WeeAppModel
    let update: MacAppUpdate

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.app.fill")
                .weeFont(size: 34)
                .foregroundStyle(WeeTheme.accent)
                .frame(width: 60, height: 60)
                .background(WeeTheme.accent.opacity(0.15), in: Circle())

            VStack(spacing: 6) {
                Text("Wee Orchestrator \(update.version.description) is available")
                    .weeFont(.title3, weight: .bold)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(model.appUpdateStatus ?? "Download, verify, install, and relaunch in one step.")
                    .weeFont(.subheadline)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button("Not now") {
                    model.availableAppUpdate = nil
                    model.appUpdateStatus = nil
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(model.isInstallingAppUpdate)

                Button {
                    Task { await model.installAvailableAppUpdate() }
                } label: {
                    HStack(spacing: 6) {
                        if model.isInstallingAppUpdate {
                            ProgressView().controlSize(.small).tint(.black)
                        }
                        Text(model.isInstallingAppUpdate ? "Installing…" : "Update and Restart")
                    }
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(model.isInstallingAppUpdate)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(WeeTheme.background)
        .preferredColorScheme(.dark)
    }
}

/// Standard SwiftUI/AppKit bridge for obtaining the NSWindow hosting this
/// view. Used to identify which native window ("tab") a ContentView instance
/// belongs to, so the per-window environment can resync when that specific
/// window regains focus.
private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
