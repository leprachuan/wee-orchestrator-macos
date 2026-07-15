import XCTest
@testable import WeeOrchestrator

@MainActor
final class KanbanEnabledTests: XCTestCase {
    // `kanbanEnabled` is backed by UserDefaults.standard, which persists
    // across test methods in the same process. Reset it so each test starts
    // from the documented default regardless of run order.
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "wee.kanban.enabled")
        super.tearDown()
    }

    /// Issue #15: the Kanban board must be fully optional. Disabling it should
    /// clear any board already in memory so a stale board can't linger behind
    /// a toggle the user just turned off, and `loadKanbanBoard` must no-op
    /// (no network fetch) while disabled.
    func test_disablingKanbanClearsBoardState() async {
        let model = WeeAppModel()
        model.kanbanBoard = KanbanBoardResponse(success: true, columns: [:], agents: [], sources: [], total: 1, repo: nil)
        model.kanbanStatusMessage = "stale"

        model.setKanbanEnabled(false)

        XCTAssertNil(model.kanbanBoard)
        XCTAssertNil(model.kanbanStatusMessage)
        XCTAssertFalse(model.kanbanEnabled)

        await model.loadKanbanBoard()
        XCTAssertNil(model.kanbanBoard, "loadKanbanBoard must not fetch while Kanban is disabled")
    }

    func test_kanbanEnabledDefaultsToTrue() {
        UserDefaults.standard.removeObject(forKey: "wee.kanban.enabled")
        let model = WeeAppModel()
        XCTAssertTrue(model.kanbanEnabled)
    }
}
