import XCTest
@testable import WeeOrchestrator

final class ChatSessionOrganizationTests: XCTestCase {
    private func session(_ id: String, title: String? = "Server title") -> HistorySessionSummary {
        HistorySessionSummary(sessionID: id, title: title, preview: nil, agent: "orchestrator", createdAt: nil, updatedAt: nil)
    }

    func test_archivedSessionIsMarkedAndCanBeRestored() {
        var organization = ChatSessionOrganization()
        organization.archive("chat-1")
        XCTAssertTrue(organization.isArchived("chat-1"))

        organization.restore("chat-1")
        XCTAssertFalse(organization.isArchived("chat-1"))
    }

    func test_customTitleOverridesServerTitleAndBlankTitleRestoresIt() {
        var organization = ChatSessionOrganization()
        let chat = session("chat-1")
        organization.rename("chat-1", to: "Release planning")
        XCTAssertEqual(organization.title(for: chat), "Release planning")

        organization.rename("chat-1", to: "  ")
        XCTAssertEqual(organization.title(for: chat), "Server title")
    }

    func test_agentColorIndexIsStableForTheSameAgent() {
        XCTAssertEqual(ChatAgentColor.index(for: "wee-dev"), ChatAgentColor.index(for: "wee-dev"))
        XCTAssertNotEqual(ChatAgentColor.index(for: "wee-dev"), ChatAgentColor.index(for: nil))
    }
}
