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

    var body: some View {
        HStack(spacing: 0) {
            workspaceRail

            ZStack {
                WeeBackground()
                sectionView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeeTheme.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 960, minHeight: 640)
        .task { await model.bootstrap() }
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
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(WeeTheme.textPrimary)
                    Text("ORCHESTRATOR")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(WeeTheme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 18)

            Text("WORKSPACE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(WeeTheme.textMuted)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            VStack(spacing: 3) {
                ForEach(AppSection.allCases) { section in
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WeeTheme.textPrimary)
                }

                HStack(spacing: 6) {
                    Image(systemName: model.activeEnvironment.symbol)
                    Text("\(model.activeEnvironment.title) API")
                    Spacer()
                    Text(model.agents.count.description)
                        .foregroundStyle(WeeTheme.accent)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WeeTheme.textSecondary)

                HStack {
                    Text(model.health?.environment ?? model.appConfig?.appEnv ?? "Not connected")
                        .font(.caption2)
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
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(selectedSection == section ? WeeTheme.accent : WeeTheme.textSecondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedSection == section ? WeeTheme.textPrimary : WeeTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(section.eyebrow)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(WeeTheme.textMuted)
                }

                Spacer(minLength: 4)
                if badgeCount(for: section) > 0 {
                    Text("\(badgeCount(for: section))")
                        .font(.system(size: 9, weight: .bold))
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
        case .chat: ChatView(model: model)
        case .kanban: KanbanView(model: model)
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
