import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case chat
    case kanban
    case tasks
    case agents
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .kanban: "Kanban"
        case .tasks: "Tasks"
        case .agents: "Agents"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .kanban: "rectangle.3.group"
        case .tasks: "bolt.fill"
        case .agents: "person.3.sequence.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @Bindable var model: WeeAppModel
    @State private var selectedSection: AppSection = .chat

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack {
                WeeBackground()
                sectionView
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .task {
            await model.bootstrap()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSection) {
            Section("Wee Orchestrator") {
                ForEach(AppSection.allCases) { section in
                    Label {
                        HStack {
                            Text(section.title)
                            Spacer()
                            if badgeCount(for: section) > 0 {
                                Text("\(badgeCount(for: section))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(badgeColor(for: section), in: Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: section.symbol)
                    }
                    .tag(section)
                }
            }

            Section("Status") {
                HStack {
                    StatusPill(
                        text: model.health?.status ?? "unknown",
                        color: model.health?.status == "ok" ? WeeTheme.accent : WeeTheme.gold,
                        symbol: model.health?.status == "ok" ? "checkmark.circle.fill" : "wifi.slash"
                    )
                    Spacer()
                }

                if let env = model.health?.environment ?? model.appConfig?.appEnv {
                    Text(env)
                        .font(.caption)
                        .foregroundStyle(WeeTheme.textSecondary)
                }
            }

            Section {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .toolbar {
            ToolbarItem {
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var sectionView: some View {
        switch selectedSection {
        case .chat:
            ChatView(model: model)
        case .kanban:
            KanbanView(model: model)
        case .tasks:
            TasksView(model: model)
        case .agents:
            AgentsView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }

    private var runningCount: Int {
        model.tasks.filter { $0.status == "running" }.count
    }

    private var dueCount: Int {
        model.kanbanBoard?.dueCards.count ?? 0
    }

    private func badgeCount(for section: AppSection) -> Int {
        switch section {
        case .kanban: dueCount
        case .tasks: runningCount
        default: 0
        }
    }

    private func badgeColor(for section: AppSection) -> Color {
        section == .kanban ? WeeTheme.gold : WeeTheme.accent
    }
}
