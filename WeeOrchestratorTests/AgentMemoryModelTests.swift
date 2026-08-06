import XCTest
@testable import WeeOrchestrator

final class AgentMemoryModelTests: XCTestCase {
    // MARK: - Durable vs. daily distinction

    func test_memoryMdIsNotDaily() {
        let entry = AgentMemoryEntry(name: "MEMORY.md", summary: "Durable facts")
        XCTAssertFalse(entry.isDaily)
    }

    func test_dailyNoteIsDaily() {
        let entry = AgentMemoryEntry(name: "daily/2026-08-06.md", summary: "Today's notes")
        XCTAssertTrue(entry.isDaily)
    }

    func test_categoryFileIsNotDaily() {
        // Category files (e.g. user_preferences.md) live alongside MEMORY.md,
        // not under daily/ -- only the daily/ prefix should count as a note.
        let entry = AgentMemoryEntry(name: "user_preferences.md", summary: "")
        XCTAssertFalse(entry.isDaily)
    }

    func test_idIsTheMemoryName() {
        let entry = AgentMemoryEntry(name: "daily/2026-08-06.md", summary: "")
        XCTAssertEqual(entry.id, "daily/2026-08-06.md")
    }

    // MARK: - Decoding: list response

    func test_decodesListResponseWithMemoryMdAndDailyNotes() throws {
        let json = """
        {
            "memories": [
                {"name": "MEMORY.md", "summary": "Durable facts"},
                {"name": "daily/2026-08-06.md", "summary": "Today's notes"}
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AgentMemoryListResponse.self, from: json)
        XCTAssertEqual(response.memories.count, 2)
        XCTAssertEqual(response.memories[0].name, "MEMORY.md")
        XCTAssertFalse(response.memories[0].isDaily)
        XCTAssertEqual(response.memories[1].name, "daily/2026-08-06.md")
        XCTAssertTrue(response.memories[1].isDaily)
    }

    /// Issue #65: "Missing or empty memory is represented cleanly, without a
    /// server error." An agent with no memories yet returns an empty list,
    /// not a 404 or error shape -- decoding must handle that cleanly too.
    func test_decodesEmptyListForAnAgentWithNoMemoriesYet() throws {
        let json = #"{"memories": []}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(AgentMemoryListResponse.self, from: json)
        XCTAssertTrue(response.memories.isEmpty)
    }

    // MARK: - Decoding: content response

    func test_decodesExistingMemoryContent() throws {
        // Double-pound delimiter: the content itself starts with "# Facts",
        // whose leading `"#` would otherwise prematurely close a `#"..."#`.
        let json = ##"{"content": "# Facts\n- one\n- two\n", "exists": true}"##.data(using: .utf8)!
        let response = try JSONDecoder().decode(AgentMemoryContentResponse.self, from: json)
        XCTAssertEqual(response.content, "# Facts\n- one\n- two\n")
        XCTAssertTrue(response.exists)
    }

    /// A missing memory file is reported as empty content with exists=false,
    /// not an error -- the view must be able to tell "empty" from "failed".
    func test_decodesMissingMemoryAsEmptyNotExists() throws {
        let json = #"{"content": "", "exists": false}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(AgentMemoryContentResponse.self, from: json)
        XCTAssertEqual(response.content, "")
        XCTAssertFalse(response.exists)
    }
}
