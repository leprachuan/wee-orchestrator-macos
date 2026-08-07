import EventKit
import Foundation

/// Issue #494: creates an Apple Reminder for a Kanban item via EventKit.
enum KanbanReminderResult {
    case created
    case alreadyExists
    case accessDenied
    case failed(String)
}

/// Self-contained (no dependency on WeeAppModel/networking) so it can be
/// called directly from a card row's context menu without threading a
/// callback through the column/board view hierarchy. Mirrors the iOS
/// client's KanbanReminderService.swift.
enum KanbanReminderService {
    /// Embedded in the reminder's notes so a repeat "Add to Reminders" on the
    /// same card can detect the existing reminder and skip creating a
    /// duplicate, without needing any local state of our own -- the source
    /// of truth is Reminders itself, so it stays correct even across
    /// reinstalls or from another device sharing the same Reminders account.
    private static func marker(for cardID: String) -> String {
        "wee-kanban-id:\(cardID)"
    }

    @MainActor
    static func addReminder(for card: KanbanCard) async -> KanbanReminderResult {
        let store = EKEventStore()
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToReminders()
        } catch {
            return .failed(error.localizedDescription)
        }
        guard granted else { return .accessDenied }

        let marker = Self.marker(for: card.id)
        if await hasExistingReminder(in: store, matching: marker) {
            return .alreadyExists
        }

        guard let calendar = store.defaultCalendarForNewReminders() else {
            return .failed("No Reminders list is available to save to.")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = card.title
        reminder.calendar = calendar

        var notesLines: [String] = []
        if card.details.isEmpty == false { notesLines.append(card.details) }
        if let url = card.url, url.isEmpty == false { notesLines.append(url) }
        notesLines.append(marker)
        reminder.notes = notesLines.joined(separator: "\n\n")

        if let dueDate = dueDate(from: card.due) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        do {
            try store.save(reminder, commit: true)
            return .created
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Returns whether a match exists rather than the EKReminder itself --
    /// EKReminder isn't Sendable, and fetchReminders' completion runs off the
    /// calling context, so handing the object itself back through the
    /// continuation would risk a data race under strict concurrency.
    private static func hasExistingReminder(in store: EKEventStore, matching marker: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let predicate = store.predicateForReminders(in: nil)
            store.fetchReminders(matching: predicate) { reminders in
                let found = reminders?.contains { $0.notes?.contains(marker) == true && $0.isCompleted == false } ?? false
                continuation.resume(returning: found)
            }
        }
    }

    /// Mirrors KanbanCard's own due-date parsing (private to KanbanView.swift
    /// there) since this file has no access to it and shouldn't reach across
    /// the view layer for it.
    private static func dueDate(from due: String?) -> Date? {
        guard let due, due.isEmpty == false else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: due) { return date }

        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: due) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: due)
    }
}
