import SwiftUI

struct TasksView: View {
    @Bindable var model: WeeAppModel
    @State private var prompt = ""
    @AppStorage("wee.tasks.scheduledCollapsed") private var scheduledTasksCollapsed = false
    @AppStorage("wee.tasks.backgroundCollapsed") private var backgroundTasksCollapsed = false

    private var running: Int { model.tasks.filter { $0.status == "running" }.count }
    private var queued: Int { model.tasks.filter { $0.status == "queued" }.count }
    private var scheduledEnabled: Int { model.scheduledJobs.filter { $0.enabled != false }.count }

    var body: some View {
        VStack(spacing: 8) {
            PageHeader(title: "Tasks", subtitle: "Launch and monitor asynchronous work", symbol: "bolt.fill") {
                StatusPill(text: "\(running) running", color: WeeTheme.emerald, symbol: "bolt.fill")
                StatusPill(text: "\(queued) queued", color: WeeTheme.gold, symbol: "clock.fill")
                StatusPill(text: "\(scheduledEnabled) scheduled", color: WeeTheme.textSecondary, symbol: "calendar")
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(CompactIconButtonStyle())
                .keyboardShortcut("r", modifiers: .command)
            }

            ScrollView {
                VStack(spacing: 8) {
                    backgroundComposer
                    HStack(alignment: .top, spacing: 8) {
                        scheduledJobsSection
                            .frame(maxWidth: .infinity, alignment: .top)
                        backgroundTasksSection
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
        .padding(10)
        .task {
            await model.loadScheduledJobs()
        }
        .sheet(item: $model.selectedTask) { detail in
            TaskDetailView(detail: detail)
                .frame(width: 560, height: 480)
        }
    }

    private var scheduledJobsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Scheduled Tasks",
                symbol: "calendar",
                summary: "\(model.scheduledJobs.count)",
                isCollapsed: $scheduledTasksCollapsed
            ) {
                Task { await model.loadScheduledJobs() }
            }

            if scheduledTasksCollapsed {
                CollapsedTaskSummary(
                    title: model.scheduledJobs.isEmpty ? (model.schedulerStatusMessage ?? "No scheduled jobs") : "\(model.scheduledJobs.count) scheduled tasks",
                    symbol: "calendar"
                )
            } else {
                if model.scheduledJobs.isEmpty {
                    EmptyTaskState(
                        title: model.schedulerStatusMessage ?? "No scheduled jobs",
                        symbol: "calendar.badge.exclamationmark",
                        minHeight: 80
                    )
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(model.scheduledJobs) { job in
                            ScheduledJobRow(job: job)
                        }
                    }
                }
            }
        }
        .padding(10)
        .glassPanel()
    }

    private var backgroundComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Describe a background task to run…", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .foregroundStyle(WeeTheme.textPrimary)
                .padding(10)
                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Picker("Agent", selection: $model.selectedAgent) {
                ForEach(model.agents) { agent in
                    Text(agent.name).tag(agent.name)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Button {
                let taskPrompt = prompt
                prompt = ""
                Task { await model.createBackgroundTask(prompt: taskPrompt) }
            } label: {
                Label("Run Task", systemImage: "play.fill")
            }
            .buttonStyle(WeePrimaryButtonStyle())
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
        }
        .padding(9)
        .glassPanel()
    }

    private var backgroundTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Background Tasks",
                symbol: "bolt.fill",
                summary: "\(model.tasks.count)",
                isCollapsed: $backgroundTasksCollapsed
            ) {
                Task { await model.refreshAll() }
            }

            if backgroundTasksCollapsed {
                CollapsedTaskSummary(
                    title: model.tasks.isEmpty ? "No background tasks" : "\(model.tasks.count) background tasks",
                    symbol: "bolt.fill"
                )
            } else {
                if model.tasks.isEmpty {
                    EmptyTaskState(title: "No background tasks", symbol: "bolt.slash", minHeight: 80)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(model.tasks) { task in
                            Button {
                                Task { await model.loadTaskDetail(task) }
                            } label: {
                                TaskRow(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
        .glassPanel()
        .animation(.easeInOut(duration: 0.18), value: scheduledTasksCollapsed)
        .animation(.easeInOut(duration: 0.18), value: backgroundTasksCollapsed)
    }
}

private struct EmptyTaskState: View {
    let title: String
    let symbol: String
    var minHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(WeeTheme.textMuted)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(18)
    }
}

private struct SectionHeader: View {
    let title: String
    let symbol: String
    let summary: String
    @Binding var isCollapsed: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isCollapsed.toggle()
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WeeTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed ? "Expand \(title)" : "Collapse \(title)")

            Image(systemName: symbol)
                .foregroundStyle(WeeTheme.accent)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WeeTheme.textPrimary)
            StatusPill(text: summary, color: WeeTheme.textSecondary)
            Spacer()
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(WeeGhostButtonStyle())
        }
    }
}

private struct CollapsedTaskSummary: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(WeeTheme.textMuted)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
    }
}

private struct TaskRow: View {
    let task: BackgroundTaskSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusPill(text: task.status, color: statusColor, symbol: statusSymbol)
                Text(task.agent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeTheme.textSecondary)
                Spacer()
                Text(task.taskID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(WeeTheme.textMuted)
            }

            Text(task.prompt)
                .font(.subheadline)
                .foregroundStyle(WeeTheme.textPrimary)
                .lineLimit(2)

            if let runtime = task.actualRuntime ?? task.runtime {
                Text([runtime, task.actualModel ?? task.model].compactMap { $0 }.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(9)
        .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
    }

    private var statusColor: Color {
        switch task.status {
        case "running": WeeTheme.accent
        case "queued": WeeTheme.gold
        case "failed": WeeTheme.danger
        default: WeeTheme.textSecondary
        }
    }

    private var statusSymbol: String {
        switch task.status {
        case "running": "bolt.fill"
        case "queued": "clock.fill"
        case "failed": "xmark.octagon.fill"
        default: "checkmark.circle.fill"
        }
    }
}

private struct ScheduledJobRow: View {
    let job: ScheduledJobSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusPill(text: job.enabled == false ? "paused" : "enabled", color: job.enabled == false ? WeeTheme.gold : WeeTheme.accent, symbol: job.enabled == false ? "pause.circle.fill" : "checkmark.circle.fill")
                Text(job.mode == "command" ? "command" : job.agent ?? "orchestrator")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeTheme.textSecondary)
                Spacer()
                Text(job.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(WeeTheme.textMuted)
                    .lineLimit(1)
            }

            Text(job.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeeTheme.textPrimary)
                .lineLimit(2)

            Text(job.displaySchedule)
                .font(.caption)
                .foregroundStyle(WeeTheme.gold)
                .lineLimit(1)

            if let task = job.task, !task.isEmpty {
                Text(task)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let nextRun = job.nextRun, !nextRun.isEmpty {
                    StatusPill(text: "Next \(nextRun.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: ""))", color: WeeTheme.accent, symbol: "calendar.badge.clock")
                }
                if job.recurring == false {
                    StatusPill(text: "one-shot", color: WeeTheme.gold, symbol: "1.circle")
                }
                if let runtime = job.runtime, !runtime.isEmpty {
                    Text([runtime, job.model].compactMap { $0 }.joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(WeeTheme.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(9)
        .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
    }
}

private struct TaskDetailView: View {
    let detail: BackgroundTaskDetail

    var body: some View {
        ZStack {
            WeeBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        StatusPill(text: detail.status, color: detail.status == "failed" ? WeeTheme.danger : WeeTheme.accent)
                        Spacer()
                        Text(detail.taskID)
                            .font(.caption.monospaced())
                            .foregroundStyle(WeeTheme.textMuted)
                    }

                    Text(detail.prompt)
                        .font(.headline)
                        .foregroundStyle(WeeTheme.textPrimary)

                    if let error = detail.error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(WeeTheme.danger)
                    }

                    if let output = detail.recentOutput, !output.isEmpty {
                        Text(output.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(WeeTheme.textSecondary)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(18)
                .glassPanel()
                .padding(18)
            }
        }
        .preferredColorScheme(.dark)
    }
}
