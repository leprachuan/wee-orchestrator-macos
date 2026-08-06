import Foundation
import Observation
import UserNotifications

/// One entry in the in-app notification center (issue #60). Mirrors a system
/// notification Wee already sends via UNUserNotificationCenter -- task
/// completion/failure and Kanban due-date reminders -- so it survives after
/// the system banner is dismissed and is reviewable from the bell icon.
struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let createdAt: Date
    var isRead: Bool
}

/// Persists Wee's existing system notifications into an in-app history with
/// read/unread state, and supplies the unread badge count for issue #60's
/// bell icon.
///
/// Must be an `NSObject` subclass to serve as `UNUserNotificationCenter`'s
/// delegate. Kept off the main actor at the class level (delegate methods
/// arrive on an arbitrary system queue) with individual mutating members
/// marked `@MainActor` so SwiftUI can bind to `notifications`/`unreadCount`
/// safely; the delegate callback hops over explicitly.
@Observable
final class NotificationCenterStore: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    @MainActor private(set) var notifications: [AppNotification] = []
    private let defaults: UserDefaults
    private let storageKey = "wee.notificationCenter.history"
    private let maxStored = 100

    @MainActor var unreadCount: Int {
        notifications.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        Task { @MainActor in load() }
    }

    @MainActor
    func record(id: String, title: String, body: String) {
        let entry = AppNotification(id: id, title: title, body: body, createdAt: Date(), isRead: false)
        // De-dupe by id: a re-delivered/updated notification (e.g. a Kanban
        // reminder rescheduled for the same card) replaces its prior entry
        // rather than piling up duplicates.
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index] = entry
        } else {
            notifications.insert(entry, at: 0)
        }
        if notifications.count > maxStored {
            notifications.removeLast(notifications.count - maxStored)
        }
        save()
    }

    @MainActor
    func markRead(id: String) {
        guard let index = notifications.firstIndex(where: { $0.id == id }), !notifications[index].isRead else { return }
        notifications[index].isRead = true
        save()
    }

    @MainActor
    func markAllRead() {
        guard notifications.contains(where: { !$0.isRead }) else { return }
        for index in notifications.indices { notifications[index].isRead = true }
        save()
    }

    @MainActor
    func clearAll() {
        notifications = []
        save()
    }

    @MainActor
    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AppNotification].self, from: data) else { return }
        notifications = decoded
    }

    @MainActor
    private func save() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        defaults.set(data, forKey: storageKey)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called by the system when a notification is about to be shown while
    /// the app is running. Task-completion notifications are already
    /// recorded synchronously at their call site (WeeAppModel.notifyCompletedTasks,
    /// which fires them with `trigger: nil` and knows the result immediately) --
    /// only the "wee.kanban." prefix is recorded here, since those are
    /// scheduled ahead of time via UNCalendarNotificationTrigger and this is
    /// the one reliable place to learn a reminder actually fired.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        let content = notification.request.content
        if identifier.hasPrefix("wee.kanban.") {
            let title = content.title
            let body = content.body
            Task { @MainActor in
                self.record(id: identifier, title: title, body: body)
            }
        }
        completionHandler([.banner, .sound, .badge])
    }
}
