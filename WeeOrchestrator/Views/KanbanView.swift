import SwiftUI

struct KanbanView: View {
    @Bindable var model: WeeAppModel
    @State private var selectedCard: KanbanCard?
    @State private var urgencyFilter: KanbanUrgencyFilter = .all
    @State private var dueFilter: KanbanDueFilter = .all
    @State private var customDueStart = Calendar.current.startOfDay(for: Date())
    @State private var customDueEnd = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var labelFilter = ""
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
        VStack(spacing: 8) {
            header
            filterControls

            ScrollView {
                VStack(spacing: 8) {
                    dueSection

                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(visibleColumns) { column in
                                KanbanColumnView(
                                    column: column,
                                    cards: cards(for: column),
                                    onSelect: { selectedCard = $0 }
                                )
                                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, alignment: .top)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.visible)
                }
            }
        }
        .padding(10)
        .task {
            await model.loadKanbanBoard()
        }
        .sheet(item: $selectedCard) { card in
            KanbanItemDetailSheet(model: model, card: card, availableLabels: availableLabels)
                .frame(minWidth: 1080, idealWidth: 1240, maxWidth: 1480, minHeight: 740, idealHeight: 880, maxHeight: 1040)
        }
    }

    private var header: some View {
        PageHeader(title: "Kanban", subtitle: "Plan, prioritize, and dispatch work", symbol: "rectangle.3.group.fill") {
            HStack(spacing: 5) {
                StatusPill(text: "\(visibleColumns.reduce(0) { $0 + cards(for: $1).count }) shown", color: WeeTheme.accent, symbol: "rectangle.3.group")
                StatusPill(text: "\(dueCount) due", color: dueCount > 0 ? WeeTheme.gold : WeeTheme.textSecondary, symbol: "bell.badge")
                if activeFilterCount > 0 {
                    StatusPill(text: "\(activeFilterCount) filters", color: WeeTheme.textSecondary, symbol: "line.3.horizontal.decrease.circle")
                }
            }
            Button {
                Task { await model.loadKanbanBoard() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(CompactIconButtonStyle())
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeeTheme.textPrimary)

                Picker("Urgency", selection: $urgencyFilter) {
                    ForEach(KanbanUrgencyFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 138)

                Picker("Due", selection: $dueFilter) {
                    ForEach(KanbanDueFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 154)

                Picker("Label", selection: $labelFilter) {
                    Text("All Labels").tag("")
                    ForEach(availableLabels, id: \.self) { label in
                        Text(label).tag(label)
                    }
                }
                .frame(width: 164)

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
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
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
                    .padding(8)
                    .glassPanel()
            }
        } else {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(WeeTheme.gold)
                    Text("DUE SOON")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(WeeTheme.textSecondary)
                    StatusPill(text: "\(cards.count)", color: WeeTheme.gold)
                }
                .fixedSize()

                Rectangle()
                    .fill(WeeTheme.divider)
                    .frame(width: 1, height: 26)

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(cards.prefix(12)) { card in
                            Button {
                                selectedCard = card
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(dueColor(for: card))
                                        .frame(width: 6, height: 6)
                                    Text(card.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WeeTheme.textPrimary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 210, alignment: .leading)
                                    Text(compactDueText(for: card))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(dueColor(for: card))
                                        .lineLimit(1)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(WeeTheme.textMuted)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
                            }
                            .buttonStyle(.plain)
                        }

                        if cards.count > 12 {
                            Text("+\(cards.count - 12) more")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WeeTheme.textSecondary)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassPanel()
        }
    }

    private func dueColor(for card: KanbanCard) -> Color {
        switch card.dueBucket {
        case "overdue": WeeTheme.danger
        case "today", "soon": WeeTheme.gold
        default: WeeTheme.textSecondary
        }
    }

    private func compactDueText(for card: KanbanCard) -> String {
        switch card.dueBucket {
        case "overdue": return "Overdue"
        case "today": return "Today"
        case "soon": return card.dueDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "Soon"
        default: return card.dueDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "Due"
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
        VStack(alignment: .leading, spacing: 8) {
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
                LazyVStack(spacing: 6) {
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
        .padding(10)
        .glassPanel()
    }
}

private struct KanbanCardRow: View {
    let card: KanbanCard

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                .lineLimit(3)

            if let due = card.due, !due.isEmpty {
                StatusPill(text: dueText(due), color: dueColor, symbol: card.dueBucket == "overdue" ? "exclamationmark.circle.fill" : "calendar")
            }

            if !card.details.isEmpty {
                Text(card.details)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
                .lineLimit(2)
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
        .padding(9)
        .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
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
    let availableLabels: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var detail: KanbanItemDetail?
    @State private var title = ""
    @State private var details = ""
    @State private var status = KanbanColumnID.todo.rawValue
    @State private var agent = ""
    @State private var due = ""
    @State private var priority = "normal"
    @State private var urgency = "normal"
    @State private var labels: [String] = []
    @State private var newLabelInput = ""
    @State private var comment = ""
    @State private var dispatchAgent = ""
    @State private var dispatchPrompt = ""
    @State private var isWorking = false
    @State private var statusMessage: String?

    private var agentNames: [String] {
        model.agents.map(\.name).filter { !$0.isEmpty }
    }

    private var allAvailableLabels: [String] {
        availableLabels
    }

    private var filteredLabelSuggestions: [String] {
        let trimmed = newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return allAvailableLabels.filter { label in
            !labels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame })
                && label.lowercased().contains(trimmed)
        }.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            modalHeader

            Rectangle()
                .fill(WeeTheme.divider)
                .frame(height: 1)

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        editor
                        commentsPanel
                    }
                    .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(WeeTheme.divider)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 10) {
                            commentPanel
                            dispatchPanel
                        }
                        .padding(12)
                    }

                    Rectangle()
                        .fill(WeeTheme.divider)
                        .frame(height: 1)

                    actionPanel
                        .padding(12)
                }
                .frame(width: 350)
                .background(WeeTheme.sidebar.opacity(0.55))
            }
        }
        .background(WeeTheme.background)
        .task {
            await load()
        }
    }

    private var modalHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WeeTheme.accent)
                .frame(width: 36, height: 36)
                .background(WeeTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("KANBAN ITEM")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(WeeTheme.textMuted)
                    StatusPill(text: KanbanColumnID(rawValue: status)?.title ?? status, color: WeeTheme.accent)
                    if let issue = card.githubIssueNumber {
                        StatusPill(text: "#\(issue)", color: WeeTheme.gold, symbol: "number")
                    }
                }
                Text(title.isEmpty ? card.title : title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WeeTheme.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let url = card.url, let link = URL(string: url) {
                Link(destination: link) {
                    Label("Open Source", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(WeeGhostButtonStyle())
            }

            Button("Done") { dismiss() }
                .buttonStyle(WeeGhostButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WeeTheme.surface)
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WeeTheme.background, in: Capsule())
                    .offset(y: 14)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Task details", systemImage: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WeeTheme.textPrimary)
                Spacer()
                if isWorking { ProgressView().controlSize(.small).tint(WeeTheme.accent) }
            }

            VStack(alignment: .leading, spacing: 6) {
                editorLabel("Title")
                TextField("Task title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .foregroundStyle(WeeTheme.textPrimary)
                    .padding(10)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
            }

            VStack(alignment: .leading, spacing: 6) {
                editorLabel("Description")
                TextEditor(text: $details)
                    .font(.body)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 270)
                    .padding(9)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    editorLabel("Status")
                    Picker("Status", selection: $status) {
                        ForEach(KanbanColumnID.allCases) { column in
                            Text(column.title).tag(column.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    editorLabel("Assigned agent")
                    TextField("Unassigned", text: $agent)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
                }

                VStack(alignment: .leading, spacing: 6) {
                    editorLabel("Due date")
                    TextField("YYYY-MM-DD", text: $due)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
                }

                VStack(alignment: .leading, spacing: 6) {
                    editorLabel("Priority")
                    TextField("normal", text: $priority)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
                }

                VStack(alignment: .leading, spacing: 6) {
                    editorLabel("Urgency")
                    Picker("Urgency", selection: $urgency) {
                        Text("Normal").tag("normal")
                        Text("Urgent").tag("urgent")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                editorLabel("Labels")
                
                if labels.isEmpty {
                    Text("No labels on this item")
                        .font(.caption)
                        .foregroundStyle(WeeTheme.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(labels, id: \.self) { label in
                            HStack(spacing: 4) {
                                Text(label)
                                    .font(.caption.weight(.medium))
                                Button {
                                    removeLabel(label)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(WeeTheme.accent.opacity(0.15), in: Capsule())
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("Add or search labels", text: $newLabelInput)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WeeTheme.glassStroke))
                            .onSubmit { submitLabelQuery() }
                        
                        if !newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           filteredLabelSuggestions.isEmpty {
                            Button {
                                addLabel(newLabelInput)
                            } label: {
                                Label("Create", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundStyle(WeeTheme.accent)
                        }
                    }
                    
                    if !filteredLabelSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredLabelSuggestions, id: \.self) { suggestion in
                                Button {
                                    addLabel(suggestion)
                                } label: {
                                    HStack {
                                        Image(systemName: "tag.fill")
                                            .foregroundStyle(WeeTheme.textSecondary)
                                        Text(suggestion)
                                            .foregroundStyle(WeeTheme.textPrimary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(WeeTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(8)
                        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
            }

            HStack {
                Text("Changes apply to the linked Kanban source.")
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textMuted)
                Spacer()
                Button {
                    Task { await save() }
                } label: {
                    Label("Save Changes", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(isWorking || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(13)
        .glassPanel()
    }

    private func editorLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(WeeTheme.textMuted)
    }

    private var commentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Add comment", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold)).foregroundStyle(WeeTheme.textPrimary)
            TextEditor(text: $comment)
                .frame(minHeight: 90)
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
        .padding(11)
        .glassPanel()
    }

    private var dispatchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Dispatch", systemImage: "paperplane.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(WeeTheme.textPrimary)

            if agentNames.isEmpty {
                TextField("Agent", text: $dispatchAgent)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Agent", selection: $dispatchAgent) {
                    ForEach(agentNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextEditor(text: $dispatchPrompt)
                .frame(minHeight: 100)
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
        .padding(11)
        .glassPanel()
    }

    private var actionPanel: some View {
        HStack(spacing: 8) {
            Button {
                Task { await complete() }
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
            .buttonStyle(WeeGhostButtonStyle())
            .frame(maxWidth: .infinity)

            Button(role: .destructive) {
                Task { await close() }
            } label: {
                Label("Close", systemImage: "xmark.circle")
            }
            .buttonStyle(WeeGhostButtonStyle())
            .frame(maxWidth: .infinity)
        }
        .disabled(isWorking)
    }

    @ViewBuilder
    private var commentsPanel: some View {
        let comments = detail?.comments ?? []
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WeeTheme.textPrimary)
                    Spacer()
                    StatusPill(text: "\(comments.count)", color: WeeTheme.textSecondary)
                }
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
        labels = userFacingLabels(card.labels)
    }

    private func populate(from item: KanbanItemDetail) {
        title = item.title; details = item.details; status = item.status
        agent = item.agent ?? ""; due = item.due ?? ""
        priority = item.priority; urgency = item.urgency
        labels = userFacingLabels(item.labels)
    }

    private func save() async {
        isWorking = true; defer { isWorking = false }
        guard let item = await model.updateKanbanItem(id: card.id, title: title, details: details, status: status, agent: agent, due: due, priority: priority, urgency: urgency, labels: labels) else { return }
        detail = item; populate(from: item); statusMessage = "Saved."
    }

    private func submitLabelQuery() {
        let query = newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exactMatch = filteredLabelSuggestions.first(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
            addLabel(exactMatch)
        } else if filteredLabelSuggestions.isEmpty && !query.isEmpty {
            addLabel(query)
        }
    }

    private func addLabel(_ value: String) {
        let label = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
        guard !label.isEmpty,
              !labels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) else {
            newLabelInput = ""
            return
        }
        labels.append(label)
        labels.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        newLabelInput = ""
    }

    private func removeLabel(_ label: String) {
        labels.removeAll { $0.caseInsensitiveCompare(label) == .orderedSame }
    }

    private func userFacingLabels(_ source: [String]) -> [String] {
        source.filter { label in
            let lower = label.lowercased()
            return !lower.hasPrefix("agent:")
                && !lower.hasPrefix("due:")
                && !lower.hasPrefix("priority:")
                && !lower.hasPrefix("status:")
                && !lower.hasPrefix("urgency:")
                && lower != "urgent"
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
