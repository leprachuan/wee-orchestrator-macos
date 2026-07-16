import SwiftUI

enum TasksViewMode {
    case background
    case scheduled
}

struct TasksView: View {
    @Bindable var model: WeeAppModel
    let mode: TasksViewMode
    @State private var prompt = ""
    @State private var scheduledEditor: ModernScheduledEditorContext?
    @AppStorage("wee.tasks.scheduledCollapsed") private var scheduledTasksCollapsed = false
    @AppStorage("wee.tasks.backgroundCollapsed") private var backgroundTasksCollapsed = false

    private var running: Int { model.tasks.filter { $0.status == "running" }.count }
    private var queued: Int { model.tasks.filter { $0.status == "queued" }.count }
    private var scheduledEnabled: Int { model.scheduledJobs.filter { $0.enabled != false }.count }

    var body: some View {
        VStack(spacing: 8) {
            PageHeader(title: pageTitle, subtitle: pageSubtitle, symbol: pageSymbol) {
                Picker("Environment", selection: environmentBinding) {
                    ForEach(WeeEnvironment.allCases) { environment in
                        Label(environment.title, systemImage: environment.symbol).tag(environment)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                if mode == .background {
                    StatusPill(text: "\(running) running", color: WeeTheme.emerald, symbol: "bolt.fill")
                    StatusPill(text: "\(queued) queued", color: WeeTheme.gold, symbol: "clock.fill")
                    StatusPill(text: "\(model.tasks.count) total", color: WeeTheme.textSecondary, symbol: "tray.full")
                } else {
                    StatusPill(text: "\(scheduledEnabled) enabled", color: WeeTheme.emerald, symbol: "calendar.badge.checkmark")
                    StatusPill(text: "\(model.scheduledJobs.count) total", color: WeeTheme.textSecondary, symbol: "calendar")
                    Button {
                        scheduledEditor = ModernScheduledEditorContext(job: nil)
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                    .buttonStyle(WeePrimaryButtonStyle())
                }
                Button {
                    Task {
                        if mode == .scheduled { await model.loadScheduledJobs() }
                        else { await model.refreshAll() }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(CompactIconButtonStyle())
                .keyboardShortcut("r", modifiers: .command)
            }

            ScrollView {
                VStack(spacing: 8) {
                    if mode == .background {
                        backgroundComposer
                        backgroundTasksSection
                            .frame(maxWidth: .infinity, alignment: .top)
                    } else {
                        scheduledJobsSection
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
        .padding(10)
        .task {
            if mode == .scheduled { await model.loadScheduledJobs() }
        }
        .sheet(item: $model.selectedTask) { detail in
            TaskDetailView(model: model, detail: detail)
                .frame(minWidth: 720, idealWidth: 860, maxWidth: 1100, minHeight: 560, idealHeight: 700, maxHeight: 900)
        }
        .sheet(item: $scheduledEditor) { context in
            ModernScheduledJobEditorSheet(model: model, job: context.job)
                .frame(minWidth: 980, idealWidth: 1120, maxWidth: 1280, minHeight: 700, idealHeight: 800, maxHeight: 920)
        }
    }

    private var pageTitle: String {
        mode == .background ? "Background Tasks" : "Scheduled Tasks"
    }

    /// Task lists and task mutations are API-scoped. Switching here updates
    /// the app's active API before a task can be viewed, created, or edited.
    private var environmentBinding: Binding<WeeEnvironment> {
        Binding(
            get: { model.activeEnvironment },
            set: { environment in
                Task {
                    await model.switchEnvironment(to: environment)
                    if mode == .scheduled { await model.loadScheduledJobs() }
                }
            }
        )
    }

    private var pageSubtitle: String {
        mode == .background
            ? "Launch and monitor asynchronous agent work"
            : "Review recurring automations and upcoming runs"
    }

    private var pageSymbol: String {
        mode == .background ? "bolt.fill" : "calendar.badge.clock"
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
                            Button {
                                scheduledEditor = ModernScheduledEditorContext(job: job)
                            } label: {
                                ScheduledJobRow(job: job)
                            }
                            .buttonStyle(.plain)
                            .help("Edit \(job.displayName)")
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

private struct ModernScheduledEditorContext: Identifiable {
    let id = UUID()
    let job: ScheduledJobSummary?
}

private enum SchedulerExecutionMode: String, CaseIterable, Identifiable {
    case ai
    case command
    var id: String { rawValue }
    var title: String { self == .ai ? "AI Task" : "Command" }
    var symbol: String { self == .ai ? "sparkles" : "terminal" }
}

private enum EditorTab: String, CaseIterable {
    case edit = "Edit"
    case history = "Execution History"
}

private struct ModernScheduledJobEditorSheet: View {
    @Bindable var model: WeeAppModel
    let job: ScheduledJobSummary?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var schedule: String
    @State private var executionMode: SchedulerExecutionMode
    @State private var agent: String
    @State private var runtime: String
    @State private var modelName: String
    @State private var permissionMode: String
    @State private var task: String
    @State private var workingDirectory: String
    @State private var recurring: Bool
    @State private var notify: Bool
    @State private var timeout: Int
    @State private var fallbackRuntime: String
    @State private var fallbackModel: String
    @State private var models: [ModelCatalogEntry] = []
    @State private var fallbackModels: [ModelCatalogEntry] = []
    @State private var isSaving = false
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationIsError = false
    @State private var errorMessage: String?
    
    @State private var selectedTab: EditorTab = .edit
    @State private var executionHistory: [ScheduledExecutionResult] = []
    @State private var isLoadingHistory = false
    @State private var historyError: String?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    init(model: WeeAppModel, job: ScheduledJobSummary?) {
        self.model = model
        self.job = job
        _name = State(initialValue: job?.name ?? "")
        _schedule = State(initialValue: job?.schedule ?? "")
        _executionMode = State(initialValue: job?.mode == "command" ? .command : .ai)
        _agent = State(initialValue: job?.agent ?? model.selectedAgent)
        _runtime = State(initialValue: job?.runtime ?? (model.selectedRuntime.isEmpty ? "claude" : model.selectedRuntime))
        _modelName = State(initialValue: job?.model ?? "")
        let storedPermission = job?.permissionMode ?? job?.mode ?? "restricted"
        _permissionMode = State(initialValue: ["restricted", "elevated", "sandboxed"].contains(storedPermission) ? storedPermission : "restricted")
        _task = State(initialValue: job?.task ?? "")
        _workingDirectory = State(initialValue: job?.workingDir ?? "/opt")
        _recurring = State(initialValue: job?.recurring ?? true)
        _notify = State(initialValue: job?.notify ?? false)
        _timeout = State(initialValue: job?.timeout ?? 300)
        _fallbackRuntime = State(initialValue: job?.fallbackRuntime ?? "")
        _fallbackModel = State(initialValue: job?.fallbackModel ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Rectangle().fill(WeeTheme.divider).frame(height: 1)
            
            if job != nil {
                HStack(spacing: 12) {
                    ForEach(EditorTab.allCases, id: \.rawValue) { tab in
                        Button(action: { selectedTab = tab }) {
                            Text(tab.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedTab == tab ? WeeTheme.accent : WeeTheme.textSecondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                        }
                        .background(selectedTab == tab ? WeeTheme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(WeeTheme.surface)
                Rectangle().fill(WeeTheme.divider).frame(height: 1)
            }

            if selectedTab == .history && job != nil {
                executionHistoryView
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 10) {
                            basicsSection
                            taskSection
                        }
                        .frame(maxWidth: .infinity, alignment: .top)

                        VStack(spacing: 10) {
                            executionSection
                            deliverySection
                            fallbackSection
                        }
                        .frame(width: 340, alignment: .top)
                    }
                    .padding(14)
                }
            }

            Rectangle().fill(WeeTheme.divider).frame(height: 1)
            editorFooter
        }
        .background(WeeTheme.background)
        .task {
            await loadModels(for: runtime, fallback: false)
            if !fallbackRuntime.isEmpty { await loadModels(for: fallbackRuntime, fallback: true) }
            if job != nil { await loadExecutionHistory() }
        }
        .task(id: selectedTab) {
            if selectedTab == .history && job != nil { await loadExecutionHistory() }
        }
        .task(id: schedule) {
            validationMessage = nil
            let value = schedule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 3 else { return }
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
                try Task.checkCancellation()
                await validateSchedule(value)
            } catch { }
        }
        .onChange(of: runtime) {
            modelName = ""
            Task { await loadModels(for: runtime, fallback: false) }
        }
        .onChange(of: fallbackRuntime) {
            fallbackModel = ""
            Task { await loadModels(for: fallbackRuntime, fallback: true) }
        }
        .confirmationDialog(
            "Delete “\(name.isEmpty ? "this scheduled task" : name)”?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let job else { return }
                Task {
                    isDeleting = true
                    try? await model.deleteScheduledJob(id: job.id)
                    isDeleting = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This scheduled task will be permanently removed. This can't be undone.")
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: job == nil ? "calendar.badge.plus" : "calendar.badge.clock")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WeeTheme.accent)
                .frame(width: 36, height: 36)
                .background(WeeTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(job == nil ? "NEW SCHEDULED TASK" : "EDIT SCHEDULED TASK")
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(WeeTheme.textMuted)
                Text(name.isEmpty ? "Untitled schedule" : name)
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(WeeTheme.textPrimary).lineLimit(1)
            }
            Spacer()
            if let job {
                Text(job.id).font(.caption.monospaced()).foregroundStyle(WeeTheme.textMuted)
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(isDeleting ? "Deleting…" : "Delete", systemImage: "trash")
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(isDeleting)
            }
            Button("Cancel") { dismiss() }
                .buttonStyle(WeeGhostButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WeeTheme.surface)
    }
    
    private var executionHistoryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Execution History", systemImage: "clock.badge.checkmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WeeTheme.textPrimary)
                    Spacer()
                    Button {
                        Task { await loadExecutionHistory() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(CompactIconButtonStyle())
                }
                
                if isLoadingHistory {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.9, anchor: .center)
                        Text("Loading execution history…")
                            .font(.subheadline)
                            .foregroundStyle(WeeTheme.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                } else if let error = historyError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(WeeTheme.danger)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(WeeTheme.danger)
                        Spacer()
                    }
                    .padding(12)
                    .background(WeeTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                } else if executionHistory.isEmpty {
                    HStack {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(WeeTheme.textMuted)
                        Text("No execution history yet")
                            .font(.subheadline)
                            .foregroundStyle(WeeTheme.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 8) {
                        ForEach(executionHistory) { result in
                            executionResultRow(result)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
    
    private func executionResultRow(_ result: ScheduledExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusPill(
                    text: result.success ? "success" : "failed",
                    color: result.success ? WeeTheme.emerald : WeeTheme.danger,
                    symbol: result.success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                
                if let timestamp = result.timestamp {
                    Text(formatDate(timestamp))
                        .font(.caption)
                        .foregroundStyle(WeeTheme.textSecondary)
                }
                
                if let duration = result.durationSeconds {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(WeeTheme.textMuted)
                }
                
                Spacer()
            }
            
            if let runtime = result.runtime {
                HStack(spacing: 8) {
                    Text(runtime)
                        .font(.caption2)
                        .foregroundStyle(WeeTheme.textMuted)
                    if let model = result.model {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(WeeTheme.textMuted)
                    }
                }
            }
            
            if let output = result.output, !output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WeeTheme.textSecondary)
                    Text(output)
                        .font(.caption.monospaced())
                        .foregroundStyle(WeeTheme.textMuted)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            
            if let error = result.error, !error.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WeeTheme.danger)
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(WeeTheme.danger)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WeeTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d, h:mm a"
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            return String(format: "%.1fm", seconds / 60)
        } else {
            return String(format: "%.1fh", seconds / 3600)
        }
    }
    
    private func loadExecutionHistory() async {
        guard let job = job else { return }
        isLoadingHistory = true
        historyError = nil
        defer { isLoadingHistory = false }
        
        do {
            executionHistory = try await model.client.scheduledJobResults(id: job.id, limit: 50)
        } catch {
            historyError = "Failed to load history: \(error.localizedDescription)"
        }
    }

    private var basicsSection: some View {
        SchedulerEditorSection(title: "Schedule", symbol: "calendar") {
            SchedulerEditorField(title: "Name") {
                styledTextField("Daily summary", text: $name)
            }
            SchedulerEditorField(title: "When") {
                styledTextField("every day at 9am", text: $schedule)
            }
            Text("Examples: “in 5 minutes”, “every Monday at 8am”, “every 6 hours”, or cron “0 9 * * 1-5”.")
                .font(.caption).foregroundStyle(WeeTheme.textMuted)

            if isValidating {
                Label("Validating schedule…", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold)).foregroundStyle(WeeTheme.textSecondary)
            } else if let validationMessage {
                Label(validationMessage, systemImage: validationIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(validationIsError ? WeeTheme.gold : WeeTheme.accent)
            } else if let cron = job?.cron, !cron.isEmpty {
                Label("Saved cron: \(cron)", systemImage: "checkmark.circle.fill")
                    .font(.caption.monospaced()).foregroundStyle(WeeTheme.accent)
            }
        }
    }

    private var taskSection: some View {
        SchedulerEditorSection(title: executionMode == .command ? "Command" : "Task prompt", symbol: executionMode.symbol) {
            TextEditor(text: $task)
                .font(.body)
                .foregroundStyle(WeeTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 230)
                .padding(9)
                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
        }
    }

    private var executionSection: some View {
        SchedulerEditorSection(title: "Execution", symbol: "gearshape.2.fill") {
            Picker("Task Type", selection: $executionMode) {
                ForEach(SchedulerExecutionMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if executionMode == .ai {
                SchedulerEditorField(title: "Agent") {
                    Picker("Agent", selection: $agent) {
                        ForEach(model.agents) { item in Text(item.name).tag(item.name) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
                SchedulerEditorField(title: "Runtime") {
                    Picker("Runtime", selection: $runtime) {
                        ForEach(runtimeChoices, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
                SchedulerEditorField(title: "Model") {
                    Picker("Model", selection: $modelName) {
                        Text("Runtime default").tag("")
                        ForEach(modelChoices, id: \.id) { Text($0.label).tag($0.id) }
                        if !modelName.isEmpty && !models.contains(where: { $0.id == modelName }) {
                            Text(modelName).tag(modelName)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
                SchedulerEditorField(title: "Permission mode") {
                    Picker("Permission", selection: $permissionMode) {
                        Text("Restricted").tag("restricted")
                        Text("Elevated").tag("elevated")
                        Text("Sandboxed").tag("sandboxed")
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                SchedulerEditorField(title: "Working directory") {
                    styledTextField("/opt", text: $workingDirectory)
                }
            }
        }
    }

    private var deliverySection: some View {
        SchedulerEditorSection(title: "Options", symbol: "slider.horizontal.3") {
            Toggle("Recurring", isOn: $recurring).tint(WeeTheme.accent)
            Text("Turn off for a one-time execution.").font(.caption).foregroundStyle(WeeTheme.textMuted)
            Toggle("Telegram notification", isOn: $notify).tint(WeeTheme.accent)
            Text("Send the result when execution completes.").font(.caption).foregroundStyle(WeeTheme.textMuted)
            SchedulerEditorField(title: "Timeout") {
                HStack {
                    Stepper(value: $timeout, in: 60...3600, step: 30) {
                        Text("\(timeout) seconds").foregroundStyle(WeeTheme.textPrimary)
                    }
                    Spacer()
                    Text(timeoutDescription).font(.caption).foregroundStyle(WeeTheme.textMuted)
                }
            }
        }
    }

    private var fallbackSection: some View {
        SchedulerEditorSection(title: "Fallback", symbol: "arrow.triangle.branch") {
            SchedulerEditorField(title: "Runtime") {
                Picker("Fallback runtime", selection: $fallbackRuntime) {
                    Text("None").tag("")
                    ForEach(runtimeChoices, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
            if !fallbackRuntime.isEmpty {
                SchedulerEditorField(title: "Model") {
                    Picker("Fallback model", selection: $fallbackModel) {
                        Text("Runtime default").tag("")
                        ForEach(fallbackModelChoices, id: \.id) { Text($0.label).tag($0.id) }
                        if !fallbackModel.isEmpty && !fallbackModels.contains(where: { $0.id == fallbackModel }) {
                            Text(fallbackModel).tag(fallbackModel)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var editorFooter: some View {
        HStack {
            if selectedTab == .history {
                Text("Execution history from the last 50 runs.")
                    .font(.caption).foregroundStyle(WeeTheme.textMuted)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(WeeTheme.danger).lineLimit(2)
            } else {
                Text(job == nil ? "Create a new scheduler job." : "Update the existing scheduler job.")
                    .font(.caption).foregroundStyle(WeeTheme.textMuted)
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(WeeGhostButtonStyle())
            if selectedTab == .edit {
                Button {
                    Task { await save() }
                } label: {
                    Label(isSaving ? "Saving…" : (job == nil ? "Create Task" : "Save Changes"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(isSaving || name.trimmed.isEmpty || schedule.trimmed.isEmpty || task.trimmed.isEmpty)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(12)
        .background(WeeTheme.surface)
    }

    private func styledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(WeeTheme.textPrimary)
            .padding(9)
            .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
    }

    private var runtimeChoices: [String] {
        var values = model.availableRuntimes.map(\.id)
        values += [runtime, fallbackRuntime].filter { !$0.isEmpty }
        if values.isEmpty { values = ["claude", "copilot", "codex", "gemini", "wee"] }
        return Array(Set(values)).sorted()
    }

    private var modelChoices: [ModelCatalogEntry] { models }
    private var fallbackModelChoices: [ModelCatalogEntry] { fallbackModels }

    private var timeoutDescription: String {
        if timeout < 60 { return "\(timeout)s" }
        if timeout < 3600 { return "\(timeout / 60) min" }
        return "1 hour"
    }

    private func loadModels(for runtime: String, fallback: Bool) async {
        guard !runtime.isEmpty else {
            if fallback { fallbackModels = [] } else { models = [] }
            return
        }
        do {
            let loaded = try await model.client.models(runtime: runtime)
            if fallback { fallbackModels = loaded } else { models = loaded }
        } catch {
            if fallback { fallbackModels = [] } else { models = [] }
        }
    }

    private func validateSchedule(_ value: String) async {
        isValidating = true
        defer { isValidating = false }
        do {
            let result = try await model.client.validateSchedule(value)
            validationIsError = result.success == false
            if let cron = result.cron, !cron.isEmpty {
                let human = result.humanReadable.map { " · \($0)" } ?? ""
                validationMessage = "\(cron)\(human)"
            } else if let next = result.nextRun, !next.isEmpty {
                validationMessage = "One-time · \(next)"
            } else {
                validationMessage = result.message ?? "Schedule will be parsed when saved."
            }
        } catch {
            validationIsError = true
            validationMessage = "Validation unavailable; the schedule can still be saved."
        }
    }

    private func save() async {
        errorMessage = nil
        guard !name.trimmed.isEmpty else { errorMessage = "Name is required."; return }
        guard !schedule.trimmed.isEmpty else { errorMessage = "Schedule is required."; return }
        guard !task.trimmed.isEmpty else { errorMessage = executionMode == .command ? "Command is required." : "Task prompt is required."; return }
        guard (60...3600).contains(timeout) else { errorMessage = "Timeout must be between 60 and 3600 seconds."; return }

        isSaving = true
        defer { isSaving = false }
        let isCommand = executionMode == .command
        let request = ScheduledJobMutationRequest(
            name: name.trimmed,
            schedule: schedule.trimmed,
            agent: isCommand ? nil : optional(agent),
            runtime: isCommand ? nil : optional(runtime),
            model: isCommand ? nil : optional(modelName),
            fallbackRuntime: isCommand ? nil : optional(fallbackRuntime),
            fallbackModel: isCommand ? nil : optional(fallbackModel),
            mode: isCommand ? "command" : permissionMode,
            task: task.trimmed,
            notify: notify,
            recurring: recurring,
            timeout: timeout,
            permissionMode: isCommand ? nil : permissionMode,
            workingDir: isCommand ? (optional(workingDirectory) ?? "/opt") : nil
        )
        do {
            try await model.saveScheduledJob(request, id: job?.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func optional(_ value: String) -> String? {
        let value = value.trimmed
        return value.isEmpty ? nil : value
    }
}

private struct SchedulerEditorSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold)).foregroundStyle(WeeTheme.textPrimary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

private struct SchedulerEditorField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(WeeTheme.textMuted)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
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
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeTheme.accent)
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

/// Issue #24: a larger detail view with full launch metadata and a
/// best-effort live log — polls GET .../logs every few seconds while the
/// task is still running/queued, since the API has no push/streaming
/// channel for background task output. Metadata is limited to what the
/// backend's detail endpoint actually returns today; it doesn't include
/// timeout or requesting identity/channel, and adding those is a backend
/// (Wee-Orchestrator API) change outside this client's repo.
private struct TaskDetailView: View {
    @Bindable var model: WeeAppModel
    let detail: BackgroundTaskDetail

    @State private var liveOutputLines: [String]?
    @State private var liveStatus: String?
    @State private var isLive = false

    private var displayedStatus: String { liveStatus ?? detail.status }
    private var displayedOutput: [String] { liveOutputLines ?? detail.recentOutput ?? [] }

    var body: some View {
        ZStack {
            WeeBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        promptSection
                        metadataGrid
                        if let error = detail.error {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(WeeTheme.danger)
                                .textSelection(.enabled)
                        }
                        logsSection
                            .id("logsBottom")
                    }
                    .padding(20)
                    .glassPanel()
                    .padding(20)
                }
                .onChange(of: displayedOutput.count) {
                    withAnimation(.snappy) { proxy.scrollTo("logsBottom", anchor: .bottom) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await pollLogsWhileActive() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatusPill(text: displayedStatus, color: statusColor, symbol: statusSymbol)
            if isLive {
                HStack(spacing: 4) {
                    Circle().fill(WeeTheme.emerald).frame(width: 6, height: 6)
                    Text("LIVE").font(.system(size: 9, weight: .bold)).tracking(0.6)
                }
                .foregroundStyle(WeeTheme.emerald)
            }
            Spacer()
            Text(detail.taskID)
                .font(.caption.monospaced())
                .foregroundStyle(WeeTheme.textMuted)
                .textSelection(.enabled)
        }
    }

    private var promptSection: some View {
        Text(detail.prompt)
            .font(.headline)
            .foregroundStyle(WeeTheme.textPrimary)
            .textSelection(.enabled)
    }

    private var metadataGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            MetadataRow(label: "Agent", value: detail.agent)
            MetadataRow(label: "Session", value: detail.sessionID ?? "—")
            MetadataRow(label: "Runtime", value: detail.actualRuntime ?? detail.runtime ?? "—")
            MetadataRow(label: "Model", value: detail.actualModel ?? detail.model ?? "—")
            if detail.usedFallback == true {
                MetadataRow(label: "Fallback runtime", value: detail.fallbackRuntime ?? "—")
                MetadataRow(label: "Fallback model", value: detail.fallbackModel ?? "—")
            }
            MetadataRow(label: "Started", value: formattedDate(detail.createdAt))
            MetadataRow(label: "Completed", value: formattedDate(detail.completedAt) ?? (isActiveStatus(displayedStatus) ? "In progress" : "—"))
            if let pid = detail.pid, pid > 0 {
                MetadataRow(label: "PID", value: "\(pid)")
            }
            if let count = detail.toolCallCount {
                MetadataRow(label: "Tool calls", value: "\(count)")
            }
        }
        .padding(12)
        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOGS")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(WeeTheme.textMuted)

            if displayedOutput.isEmpty {
                Text("No output yet.")
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textMuted)
                    .padding(12)
            } else {
                Text(displayedOutput.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(WeeTheme.textSecondary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func isActiveStatus(_ status: String) -> Bool {
        status == "running" || status == "queued"
    }

    private func pollLogsWhileActive() async {
        guard isActiveStatus(detail.status) else { return }
        isLive = true
        defer { isLive = false }
        while !Task.isCancelled {
            if let logs = try? await model.client.backgroundTaskLogs(id: detail.taskID) {
                liveOutputLines = logs.outputLines
                liveStatus = logs.status
                if !isActiveStatus(logs.status) { break }
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func formattedDate(_ raw: String?) -> String? {
        guard let date = BackgroundTaskOrdering.date(from: raw) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private var statusColor: Color {
        switch displayedStatus {
        case "running": WeeTheme.accent
        case "queued": WeeTheme.gold
        case "failed": WeeTheme.danger
        default: WeeTheme.emerald
        }
    }

    private var statusSymbol: String {
        switch displayedStatus {
        case "running": "bolt.fill"
        case "queued": "clock.fill"
        case "failed": "xmark.octagon.fill"
        default: "checkmark.circle.fill"
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(WeeTheme.textMuted)
            Text(value ?? "—")
                .font(.caption.weight(.medium))
                .foregroundStyle(WeeTheme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct ScheduledEditorContext: Identifiable {
    var id: String { job?.jobID ?? UUID().uuidString }
    let job: ScheduledJobSummary?
}

private struct ScheduledJobEditorSheet: View {
    @Bindable var model: WeeAppModel
    let job: ScheduledJobSummary?
    
    @State private var name = ""
    @State private var schedule = ""
    @State private var scheduleValidationMessage = ""
    @State private var scheduleValidationStatus: String? = nil
    @State private var nextRun = ""
    @State private var agent = ""
    @State private var runtime = ""
    @State private var model_runtime = ""
    @State private var fallbackRuntime = ""
    @State private var fallbackModel_runtime = ""
    @State private var mode = "prompt"
    @State private var task = ""
    @State private var notify = true
    @State private var recurring = true
    @State private var timeout: Int = 300
    @State private var permissionMode = ""
    @State private var workingDir = ""
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var scheduleValidationInProgress = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            WeeBackground()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job == nil ? "Create Scheduled Task" : "Edit Scheduled Task")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WeeTheme.textPrimary)
                        Text(job == nil ? "Set up a new recurring or one-shot automation" : "Update this scheduled task")
                            .font(.caption)
                            .foregroundStyle(WeeTheme.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(WeeTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(WeeTheme.surfaceRaised)
                .overlay(Divider(), alignment: .bottom)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            LabeledTextField(label: "Task Name", text: $name, placeholder: "My scheduled task")
                            
                            LabeledTextField(label: "Task Prompt/Command", text: $task, placeholder: "Enter the task prompt", isMultiline: true)
                        }
                        
                        Group {
                            LabeledTextField(label: "Schedule", text: $schedule, placeholder: "every day at 9am")
                            
                            if !scheduleValidationMessage.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: scheduleValidationStatus == "valid" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundStyle(scheduleValidationStatus == "valid" ? WeeTheme.accent : WeeTheme.gold)
                                    Text(scheduleValidationMessage)
                                        .font(.caption)
                                        .foregroundStyle(scheduleValidationStatus == "valid" ? WeeTheme.accent : WeeTheme.gold)
                                    Spacer()
                                }
                                .padding(12)
                                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                            }
                            
                            if !nextRun.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(WeeTheme.gold)
                                    Text("Next run: \(nextRun)")
                                        .font(.caption)
                                        .foregroundStyle(WeeTheme.textSecondary)
                                    Spacer()
                                }
                                .padding(12)
                                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        
                        Divider()
                            .foregroundStyle(WeeTheme.glassStroke)
                        
                        Group {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Mode")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WeeTheme.textSecondary)
                                    Picker("Mode", selection: $mode) {
                                        Text("Prompt").tag("prompt")
                                        Text("Command").tag("command")
                                    }
                                    .pickerStyle(.segmented)
                                }
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Recurring")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WeeTheme.textSecondary)
                                    Toggle("", isOn: $recurring)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Notify on completion")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WeeTheme.textSecondary)
                                    Toggle("", isOn: $notify)
                                }
                                Spacer()
                            }
                        }
                        
                        Divider()
                            .foregroundStyle(WeeTheme.glassStroke)
                        
                        Group {
                            Picker("Agent", selection: $agent) {
                                Text("No agent").tag("")
                                ForEach(model.agents, id: \.name) { a in
                                    Text(a.name).tag(a.name)
                                }
                            }
                            
                            LabeledTextField(label: "Runtime", text: $runtime, placeholder: "e.g., claude, gpt-4")
                            LabeledTextField(label: "Model", text: $model_runtime, placeholder: "e.g., claude-opus, gpt-4-turbo")
                            
                            LabeledTextField(label: "Fallback Runtime", text: $fallbackRuntime, placeholder: "Optional")
                            LabeledTextField(label: "Fallback Model", text: $fallbackModel_runtime, placeholder: "Optional")
                        }
                        
                        Divider()
                            .foregroundStyle(WeeTheme.glassStroke)
                        
                        Group {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Timeout (seconds)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WeeTheme.textSecondary)
                                    TextField("300", value: $timeout, format: .number)
                                        .textFieldStyle(.plain)
                                        .padding(8)
                                        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                                }
                                Spacer()
                            }
                            
                            LabeledTextField(label: "Working Directory", text: $workingDir, placeholder: "Optional")
                            LabeledTextField(label: "Permission Mode", text: $permissionMode, placeholder: "e.g., restricted")
                        }
                        
                        if !errorMessage.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(WeeTheme.danger)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(WeeTheme.danger)
                                Spacer()
                            }
                            .padding(12)
                            .background(WeeTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                        
                        if !successMessage.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(WeeTheme.accent)
                                Text(successMessage)
                                    .font(.caption)
                                    .foregroundStyle(WeeTheme.accent)
                                Spacer()
                            }
                            .padding(12)
                            .background(WeeTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(16)
                }
                
                Divider()
                    .foregroundStyle(WeeTheme.glassStroke)
                
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(WeeGhostButtonStyle())
                    
                    Spacer()
                    
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8, anchor: .center)
                        } else {
                            Text(job == nil ? "Create" : "Save")
                        }
                    }
                    .buttonStyle(WeePrimaryButtonStyle())
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
                .background(WeeTheme.surfaceRaised)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadExistingJobIfEditing()
        }
        .onChange(of: schedule) { old, new in
            if !new.isEmpty {
                Task { await validateSchedule() }
            }
        }
    }
    
    private func loadExistingJobIfEditing() {
        guard let job else { return }
        
        name = job.name ?? ""
        schedule = job.schedule ?? ""
        agent = job.agent ?? ""
        runtime = job.runtime ?? ""
        model_runtime = job.model ?? ""
        fallbackRuntime = job.fallbackRuntime ?? ""
        fallbackModel_runtime = job.fallbackModel ?? ""
        mode = job.mode ?? "prompt"
        task = job.task ?? ""
        notify = job.notify ?? true
        recurring = job.recurring ?? true
        timeout = job.timeout ?? 300
        permissionMode = job.permissionMode ?? ""
        workingDir = job.workingDir ?? ""
        nextRun = job.nextRun ?? ""
    }
    
    private func validateSchedule() async {
        scheduleValidationInProgress = true
        defer { scheduleValidationInProgress = false }
        
        do {
            let response = try await model.client.validateSchedule(schedule)
            if response.success == true {
                scheduleValidationStatus = "valid"
                scheduleValidationMessage = response.humanReadable ?? "Schedule is valid"
                nextRun = response.nextRun ?? ""
            } else {
                scheduleValidationStatus = "invalid"
                scheduleValidationMessage = response.message ?? "Invalid schedule"
                nextRun = ""
            }
        } catch {
            scheduleValidationStatus = "invalid"
            scheduleValidationMessage = error.localizedDescription
            nextRun = ""
        }
    }
    
    private func validateAndSave() async {
        errorMessage = ""
        successMessage = ""
        isSaving = true
        defer { isSaving = false }
        
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Task name is required"
            return
        }
        
        guard !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Schedule is required"
            return
        }
        
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Task prompt/command is required"
            return
        }
        
        let request = ScheduledJobMutationRequest(
            name: name,
            schedule: schedule,
            agent: agent.isEmpty ? nil : agent,
            runtime: runtime.isEmpty ? nil : runtime,
            model: model_runtime.isEmpty ? nil : model_runtime,
            fallbackRuntime: fallbackRuntime.isEmpty ? nil : fallbackRuntime,
            fallbackModel: fallbackModel_runtime.isEmpty ? nil : fallbackModel_runtime,
            mode: mode,
            task: task,
            notify: notify,
            recurring: recurring,
            timeout: timeout,
            permissionMode: permissionMode.isEmpty ? nil : permissionMode,
            workingDir: workingDir.isEmpty ? nil : workingDir
        )
        
        do {
            try await model.saveScheduledJob(request, id: job?.jobID)
            successMessage = job == nil ? "Scheduled task created successfully" : "Scheduled task updated successfully"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isMultiline: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeTheme.textSecondary)
            
            if isMultiline {
                TextEditor(text: $text)
                    .font(.caption.monospaced())
                    .foregroundStyle(WeeTheme.textPrimary)
                    .padding(8)
                    .frame(minHeight: 60)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
            } else {
                TextField(placeholder, text: $text)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .padding(8)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
