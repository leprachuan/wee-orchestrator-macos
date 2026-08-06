import XCTest
@testable import WeeOrchestrator

@MainActor
final class NotificationCenterStoreTests: XCTestCase {
    private func makeStore() -> NotificationCenterStore {
        // Isolated UserDefaults suite per test so persistence doesn't leak
        // between tests or into the real app's stored notification history.
        let suiteName = "NotificationCenterStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return NotificationCenterStore(defaults: defaults)
    }

    func test_startsEmpty() {
        let store = makeStore()
        XCTAssertTrue(store.notifications.isEmpty)
        XCTAssertEqual(store.unreadCount, 0)
    }

    func test_recordInsertsAtTheFrontAsUnread() {
        let store = makeStore()
        store.record(id: "a", title: "First", body: "Body A")
        store.record(id: "b", title: "Second", body: "Body B")

        XCTAssertEqual(store.notifications.map(\.id), ["b", "a"], "Newest first")
        XCTAssertEqual(store.unreadCount, 2)
        XCTAssertFalse(store.notifications[0].isRead)
    }

    func test_recordingTheSameIDAgainReplacesRatherThanDuplicates() {
        let store = makeStore()
        store.record(id: "wee.kanban.card-1", title: "TODO Due Today", body: "Original")
        store.markRead(id: "wee.kanban.card-1")
        store.record(id: "wee.kanban.card-1", title: "TODO Due Today", body: "Updated")

        XCTAssertEqual(store.notifications.count, 1)
        XCTAssertEqual(store.notifications[0].body, "Updated")
        XCTAssertFalse(store.notifications[0].isRead, "A re-delivered notification should count as unread again")
    }

    func test_markReadClearsUnreadCountForThatEntryOnly() {
        let store = makeStore()
        store.record(id: "a", title: "A", body: "")
        store.record(id: "b", title: "B", body: "")
        store.markRead(id: "a")

        XCTAssertEqual(store.unreadCount, 1)
        XCTAssertTrue(store.notifications.first(where: { $0.id == "a" })!.isRead)
        XCTAssertFalse(store.notifications.first(where: { $0.id == "b" })!.isRead)
    }

    func test_markReadOnUnknownIDIsANoOp() {
        let store = makeStore()
        store.record(id: "a", title: "A", body: "")
        store.markRead(id: "does-not-exist")
        XCTAssertEqual(store.unreadCount, 1)
    }

    func test_markAllReadClearsEveryUnreadCount() {
        let store = makeStore()
        store.record(id: "a", title: "A", body: "")
        store.record(id: "b", title: "B", body: "")
        store.record(id: "c", title: "C", body: "")
        store.markAllRead()

        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.notifications.allSatisfy(\.isRead))
    }

    func test_clearAllRemovesEverything() {
        let store = makeStore()
        store.record(id: "a", title: "A", body: "")
        store.clearAll()
        XCTAssertTrue(store.notifications.isEmpty)
    }

    /// Bounded history: an unbounded log would grow forever across a long
    /// app lifetime purely from routine task-completion notifications.
    func test_historyIsBoundedToTheMostRecentEntries() {
        let store = makeStore()
        for i in 0..<150 {
            store.record(id: "task-\(i)", title: "Task \(i)", body: "")
        }
        XCTAssertEqual(store.notifications.count, 100)
        // Newest survive, oldest are dropped.
        XCTAssertEqual(store.notifications.first?.id, "task-149")
        XCTAssertEqual(store.notifications.last?.id, "task-50")
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        let suiteName = "NotificationCenterStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let first = NotificationCenterStore(defaults: defaults)
        first.record(id: "a", title: "Persisted", body: "Body")
        first.markRead(id: "a")

        let second = NotificationCenterStore(defaults: defaults)
        // Loading happens via a Task hop to the main actor in init(); this
        // test runs on the main actor already, so by the time we read
        // `notifications` the load's continuation has had a chance to run.
        let expectation = expectation(description: "load")
        Task { @MainActor in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(second.notifications.count, 1)
        XCTAssertEqual(second.notifications.first?.title, "Persisted")
        XCTAssertTrue(second.notifications.first?.isRead ?? false)
    }
}
