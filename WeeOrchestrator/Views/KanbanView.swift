import SwiftUI

struct KanbanView: View {
    @Bindable var model: WeeAppModel
    @State private var selectedCard: KanbanCard?
    @State private var urgencyFilter: KanbanUrgencyFilter = .all
    @State private var dueFilter: KanbanDueFilter = .all
    @State private var customDueStart = Calendar.current.startOfDay(for: Date())
    @State private var customDueEnd = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var labelFilter = ""
    @State private var isDueSoonExpanded = true
    @State private var showDoneColumn = false

    private var board: KanbanBoardResponse? {
        model.kanbanBoard
    }

    private var dueCount: Int {
        filteredDueCards.count
    }

    private var visibleColumns: [KanbanColumnID] {
        showDoneColumn ? KanbanColumnID.allCases : KanbanColumnID.allCases.filter { $0 != .done }
    }

    private var allCards: [KanbanCard] {
        KanbanColumnID.allCases.flatMap { board?.columns[$0.rawValue] ?? [] }
    }

    private var filteredDueCards: [KanbanCard] {
        filteredCards(board?.dueCards ?? [])
    }

    private var availableLabels: [String] {
        Array(Set(allCards.flatMap(\.displayLabels))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var activeFilterCount: Int {
        (urgencyFilter == .all ? 0 : 1) + (dueFilter == .all ? 0 : 1) + (labelFilter.isEmpty ? 0 : 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            filterControls

            ScrollView {
                VStack(spacing: 12) {
                    dueSection

                    HStack(alignment: .top, spacing: 12) {
                        ForEach(visibleColumns) { column in
                            KanbanColumnView(
                                column: column,
                                cards: cards(for: column),
                                onSelect: { selectedCard = $0 }
                            )
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .task {
            await model.loadKanbanBoard()
        }
        .sheet(item: $selectedCard) { card in
            KanbanItemDetailSheet(model: model, card: card)
                .frame(minWidth: 760, idealWidth: 920, maxWidth: 1100, minHeight: 680, idealHeight: 820, maxHeight: 920)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Kanban")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WeeTheme.textPrimary)
                HStack {
                    StatusPill(text: "\(visibleColumns.reduce(0) { $0 + cards(for: $1).count }) shown", color: WeeTheme.accent, symbol: "rectangle.3.group")
                    StatusPill(text: "\(dueCount) due", color: dueCount > 0 ? WeeTheme.gold : WeeTheme.textSecondary, symbol: "bell.badge")
                    if activeFilterCount > 0 {
                        StatusPill(text: "\(activeFilterCount) filters", color: WeeTheme.textSecondary, symbol: "line.3.horizontal.decrease.circle")
                    }
                    if let repo = board?.repo, !repo.isEmpty {
                        StatusPill(text: "GitHub", color: WeeTheme.textSecondary, symbol: "number")
                    }
                }
            }
            Spacer()
            Button {
                Task { await model.loadKanbanBoard() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(WeeGhostButtonStyle())
        }
        .padding(14)
        .glassPanel()
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeeTheme.textPrimary)

                Picker("Urgency", selection: $urgencyFilter) {
                    ForEach(KanbanUrgencyFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 150)

                Picker("Due", selection: $dueFilter) {
                    ForEach(KanbanDueFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 170)

                Picker("Label", selection: $labelFilter) {
                    Text("All Labels").tag("")
                    ForEach(availableLabels, id: \.self) { label in
                        Text(label).tag(label)
                    }
                }
                .frame(width: 180)

                Toggle("Show Done", isOn: $showDoneColumn)
                    .toggleStyle(.checkbox)

                Spacer()

                if activeFilterCount > 0 {
                    Button("Clear") {
                        urgencyFilter = .all
                        dueFilter = .all
                        labelFilter = ""
                    }
                    .buttonStyle(WeeGhostButtonStyle())
                }
            }

            if dueFilter == .custom {
                customDateControls
            }
        }
        .padding(14)
        .glassPanel()
    }

    private var customDateControls: some View {
        HStack(spacing: 12) {
            Label("Custom Due Range", systemImage: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeTheme.textSecondary)
            DatePicker("Start", selection: $customDueStart, displayedComponents: .date)
                .datePickerStyle(.compact)
            DatePicker("End", selection: $customDueEnd, displayedComponents: .date)
                .datePickerStyle(.compact)
            Spacer()
        }
    }

    @ViewBuilder
    private var dueSection: some View {
        let cards = filteredDueCards
        if cards.isEmpty {
            if let status = model.kanbanStatusMessage {
                EmptyKanbanState(title: status, symbol: "rectangle.stack.badge.minus")
                    .padding(14)
                    .glassPanel()
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.snappy) {
                        isDueSoonExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isDueSoonExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WeeTheme.textSecondary)
                        Image(systemName: "bell.badge")
                            .foregroundStyle(WeeTheme.gold)
                        Text("Due Soon")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WeeTheme.textPrimary)
                        Spacer()
                        StatusPill(text: "\(cards.count)", color: WeeTheme.gold)
                    }
                }
                .buttonStyle(.plain)

                if isDueSoonExpanded {
                    LazyVStack(spacing: 10) {
                        ForEach(cards.prefix(6)) { card in
                            KanbanCardRow(card: card)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCard = card
                                }
                        }
                    }
                }
            }
            .padding(14)
            .glassPanel()
        }
    }

    private func cards(for column: KanbanColumnID) -> [KanbanCard] {
        filteredCards(board?.columns[column.rawValue] ?? [])
    }

    private func filteredCards(_ cards: [KanbanCard]) -> [KanbanCard] {
        cards.filter { card in
            urgencyFilter.matches(card)
                && dueFilter.matches(card, customStart: customDueStart, customEnd: customDueEnd)
                && (labelFilter.isEmpty || card.displayLabels.contains(labelFilter))
        }
    }
}

private enum KanbanUrgencyFilter: String, CaseIterable, Identifiable {
    case all
    case urgent
    case normal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Urgency"
        case .urgent: "Urgent"
        case .normal: "Normal"
        }
    }

    func matches(_ card: KanbanCard) -> Bool {
        switch self {
        case .all: true
        case .urgent: card.urgency == "urgent"
        case .normal: card.urgency != "urgent"
        }
    }
}

private enum KanbanDueFilter: String, CaseIterable, Identifiable {
    case all
    case overdue
    case today
    case soon
    case future
    case custom
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Due Dates"
        case .overdue: "Overdue"
        case .today: "Today"
        case .soon: "Soon"
        case .future: "Future"
        case .custom: "Custom"
        case .none: "No Due Date"
        }
    }

    func matches(_ card: KanbanCard, customStart: Date, customEnd: Date) -> Bool {
        switch self {
        case .all: return true
        case .overdue: return card.dueBucket == "overdue"
        case .today: return card.dueBucket == "today"
        case .soon: return card.dueBucket == "soon"
        case .future: return card.dueBucket == "future"
        case .custom:
            guard let dueDate = card.dueDate else { return false }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let endStart = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) ?? endStart
            return dueDate >= start && dueDate <= end
        case .none: return card.dueBucket == "none"
        }
    }
}

private extension KanbanCard {
    var dueDate: Date? {
        guard let due, !due.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: due) {
            return date
        }

        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: due) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: due)
    }

    var displayLabels: [String] {
        labels.filter { label in
            let lower = label.lowercased()
            return !lower.hasPrefix("agent:")
                && !lower.hasPrefix("due:")
                && !lower.hasPrefix("priority:")
                && !lower.hasPrefix("status:")
                && !lower.hasPrefix("urgency:")
                && lower != "urgent"
        }
    }
}

private struct KanbanColumnView: View {
    let column: KanbanColumnID
    let cards: [KanbanCard]
    let onSelect: (KanbanCard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: column.symbol)
                    .foregroundStyle(WeeTheme.accent)
                Text(column.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WeeTheme.textPrimary)
                Spacer()
                StatusPill(text: "\(cards.count)", color: WeeTheme.textSecondary)
            }

            if cards.isEmpty {
                EmptyKanbanState(title: "No cards", symbol: "tray")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(cards) { card in
                        KanbanCardRow(card: card)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(card)
                            }
                    }
                }
            }
        }
        .padding(14)
        .glassPanel()
    }
}

private struct KanbanCardRow: View {
    let card: KanbanCard

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                StatusPill(text: card.source, color: card.source == "github" ? WeeTheme.gold : WeeTheme.accent, symbol: card.source == "github" ? "number" : "doc.text")
                if let agent = card.agent, !agent.isEmpty {
                    Text(agent)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WeeTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeeTheme.textPrimary)
                .lineLimit(4)

            if let due = card.due, !due.isEmpty {
                StatusPill(text: dueText(due), color: dueColor, symbol: card.dueBucket == "overdue" ? "exclamationmark.circle.fill" : "calendar")
            }

            if !card.details.isEmpty {
                Text(card.details)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if card.urgency == "urgent" {
                    StatusPill(text: "urgent", color: WeeTheme.danger, symbol: "exclamationmark.triangle.fill")
                } else if card.priority != "normal" {
                    StatusPill(text: card.priority, color: WeeTheme.gold, symbol: "flag.fill")
                }

                if let issue = card.githubIssueNumber {
                    Text("#\(issue)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(WeeTheme.textMuted)
                }

                Spacer()

                if let url = card.url, let link = URL(string: url) {
                    Link(destination: link) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .foregroundStyle(WeeTheme.accent)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(WeeTheme.glassStroke))
    }

    private var dueColor: Color {
        switch card.dueBucket {
        case "overdue": WeeTheme.danger
        case "today", "soon": WeeTheme.gold
        default: WeeTheme.textSecondary
        }
    }

    private func dueText(_ value: String) -> String {
        let short = value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
        switch card.dueBucket {
        case "overdue": return "Overdue \(short)"
        case "today": return "Today \(short)"
        case "soon": return "Soon \(short)"
        default: return short
        }
    }
}

private struct KanbanItemDetailSheet: View {
    @Bindable var model: WeeAppModel
    let card: KanbanCard
    @Environment(\.dismiss) private var dismiss

    @State private var detail: KanbanItemDetail?
    @State private var title = ""
    @State private var details = ""
    @State private var status = KanbanColumnID.todo.rawValue
    @State private var agent = ""
    @State private var due = ""
    @State private var priority = "normal"
    @State private var urgency = "normal"
    @State private var comment = ""
    @State private var dispatchAgent = ""
    @State private var dispatchPrompt = ""
    @State private var isWorking = false
    @State private var statusMessage: String?

    private var agentNames: [String] {
        model.agents.map(\.name).filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TODO Detail")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WeeTheme.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    editor
                    commentPanel
                    dispatchPanel
                    actionPanel
                    commentsPanel
                }
                .padding(16)
            }
        }
        .background(WeeTheme.background)
        .task {
            await load()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusPill(text: detail?.repo ?? "GitHub", color: WeeTheme.gold, symbol: "number")
                if let issue = card.githubIssueNumber {
                    StatusPill(text: "#\(issue)", color: WeeTheme.textSecondary)
                }
                Spacer()
            }
            Text(title.isEmpty ? card.title : title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WeeTheme.textPrimary)
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.accent)
            }
        }
        .padding(14)
        .glassPanel()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeeTheme.textPrimary)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $details)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Picker("Status", selection: $status) {
                    ForEach(KanbanColumnID.allCases) { column in
                        Text(column.title).tag(column.rawValue)
                    }
                }
                .frame(width: 180)

                TextField("Agent", text: $agent)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                TextField("Due date", text: $due)
                    .textFieldStyle(.roundedBorder)

                TextField("Priority", text: $priority)
                    .textFieldStyle(.roundedBorder)

                Picker("Urgency", selection: $urgency) {
                    Text("normal").tag("normal")
                    Text("urgent").tag("urgent")
                }
                .frame(width: 120)
            }

            Button {
                Task { await save() }
            } label: {
                Label("Save Changes", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(WeePrimaryButtonStyle())
            .disabled(isWorking || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .glassPanel()
    }

    private var commentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comment")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeeTheme.textPrimary)
            TextEditor(text: $comment)
                .frame(minHeight: 70)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            Button {
                Task { await addComment() }
            } label: {
                Label("Add Comment", systemImage: "text.bubble")
            }
            .buttonStyle(WeeGhostButtonStyle())
            .disabled(isWorking || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .glassPanel()
    }

    private var dispatchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dispatch")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeeTheme.textPrimary)

            if agentNames.isEmpty {
                TextField("Agent", text: $dispatchAgent)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Agent", selection: $dispatchAgent) {
                    ForEach(agentNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(width: 200)
            }

            TextEditor(text: $dispatchPrompt)
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))

            Button {
                Task { await dispatchItem() }
            } label: {
                Label("Dispatch to Agent", systemImage: "paperplane.fill")
            }
            .buttonStyle(WeePrimaryButtonStyle())
            .disabled(isWorking || dispatchAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .glassPanel()
    }

    private var actionPanel: some View {
        HStack(spacing: 10) {
            Button {
                Task { await complete() }
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
            .buttonStyle(WeeGhostButtonStyle())

            Button(role: .destructive) {
                Task { await close() }
            } label: {
                Label("Close", systemImage: "xmark.circle")
            }
            .buttonStyle(WeeGhostButtonStyle())
        }
        .disabled(isWorking)
    }

    @ViewBuilder
    private var commentsPanel: some View {
        let comments = detail?.comments ?? []
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Comments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeeTheme.textPrimary)
                ForEach(comments) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.author?.login ?? "comment")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WeeTheme.textSecondary)
                        Text(item.body)
                            .font(.caption)
                            .foregroundStyle(WeeTheme.textPrimary)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .glassPanel()
        }
    }

    private func load() async {
        if dispatchAgent.isEmpty {
            dispatchAgent = card.agent ?? model.selectedAgent
            if dispatchAgent.isEmpty { dispatchAgent = agentNames.first ?? "" }
        }
        guard let item = await model.loadKanbanItem(id: card.id) else {
            populate(from: card)
            return
        }
        detail = item
        populate(from: item)
    }

    private func populate(from card: KanbanCard) {
        title = card.title; details = card.details; status = card.status
        agent = card.agent ?? ""; due = card.due ?? ""
        priority = card.priority; urgency = card.urgency
    }

    private func populate(from item: KanbanItemDetail) {
        title = item.title; details = item.details; status = item.status
        agent = item.agent ?? ""; due = item.due ?? ""
        priority = item.priority; urgency = item.urgency
    }

    private func save() async {
        isWorking = true; defer { isWorking = false }
        guard let item = await model.updateKanbanItem(id: card.id, title: title, details: details, status: status, agent: agent, due: due, priority: priority, urgency: urgency) else { return }
        detail = item; populate(from: item); statusMessage = "Saved."
    }

    private func addComment() async {
        isWorking = true; defer { isWorking = false }
        guard let item = await model.commentKanbanItem(id: card.id, body: comment) else { return }
        detail = item; comment = ""; statusMessage = "Comment added."
    }

    private func dispatchItem() async {
        isWorking = true; defer { isWorking = false }
        guard let response = await model.dispatchKanbanItem(id: card.id, agent: dispatchAgent, prompt: dispatchPrompt) else { return }
        detail = response.item; populate(from: response.item); statusMessage = "Dispatched as \(response.task.taskID)."
    }

    private func complete() async {
        isWorking = true; defer { isWorking = false }
        guard let item = await model.completeKanbanItem(id: card.id) else { return }
        detail = item; populate(from: item); statusMessage = "Marked complete."
    }

    private func close() async {
        isWorking = true; defer { isWorking = false }
        guard let item = await model.closeKanbanItem(id: card.id) else { return }
        detail = item; populate(from: item); statusMessage = "Closed."
    }
}

private struct EmptyKanbanState: View {
    let title: String
    let symbol: String

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
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(18)
    }
}
