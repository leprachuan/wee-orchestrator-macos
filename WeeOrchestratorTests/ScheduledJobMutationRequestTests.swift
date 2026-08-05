import XCTest
@testable import WeeOrchestrator

final class ScheduledJobMutationRequestTests: XCTestCase {
    private func makeRequest(permissionMode: String? = "restricted") -> ScheduledJobMutationRequest {
        ScheduledJobMutationRequest(
            name: "Daily summary",
            schedule: "every day at 9am",
            agent: "orchestrator",
            runtime: "codex",
            model: nil,
            fallbackRuntime: nil,
            fallbackModel: nil,
            mode: "restricted",
            task: "Summarize the day",
            notify: true,
            recurring: true,
            timeout: 300,
            permissionMode: permissionMode,
            workingDir: nil
        )
    }

    func test_legacySchedulerRetryPayloadOmitsOnlyPermissionMode() throws {
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(makeRequest())) as? [String: Any]
        let fallback = try JSONSerialization.jsonObject(with: JSONEncoder().encode(makeRequest().withoutPermissionMode())) as? [String: Any]

        XCTAssertEqual(original?["permission_mode"] as? String, "restricted")
        XCTAssertNil(fallback?["permission_mode"])
        XCTAssertEqual(fallback?["name"] as? String, "Daily summary")
        XCTAssertEqual(fallback?["schedule"] as? String, "every day at 9am")
        XCTAssertEqual(fallback?["mode"] as? String, "restricted")
    }

    func test_legacySchedulerRetryOnlyMatchesTheKnownSchemaError() {
        let request = makeRequest()
        XCTAssertTrue(WeeAPIClient.shouldRetryScheduledJobWithoutPermissionMode(
            .httpStatus(404, #"{\"detail\":\"Unknown fields: permission_mode\"}"#),
            job: request
        ))
        XCTAssertFalse(WeeAPIClient.shouldRetryScheduledJobWithoutPermissionMode(
            .httpStatus(404, "Unknown fields: runtime"),
            job: request
        ))
        XCTAssertFalse(WeeAPIClient.shouldRetryScheduledJobWithoutPermissionMode(
            .httpStatus(500, "Unknown fields: permission_mode"),
            job: request
        ))
        XCTAssertFalse(WeeAPIClient.shouldRetryScheduledJobWithoutPermissionMode(
            .httpStatus(404, "Unknown fields: permission_mode"),
            job: makeRequest(permissionMode: nil)
        ))
    }
}
