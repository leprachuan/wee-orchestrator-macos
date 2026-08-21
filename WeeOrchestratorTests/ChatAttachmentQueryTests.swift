import XCTest
@testable import WeeOrchestrator

/// Regression test: the macOS client uploaded attachments via
/// `/api/v1/sessions/{id}/upload`, which only stages the file on disk and
/// returns its path -- it never touches the prompt sent to the agent. The
/// old query-building logic dropped the uploaded path whenever the user also
/// typed text (the common case), so the agent had no way to know an
/// attachment existed and would ask the user to send it again. `buildQuery`
/// now always appends uploaded file paths, mirroring the WebUI's
/// `sendMessage()`.
@MainActor
final class ChatAttachmentQueryTests: XCTestCase {
    func test_promptWithNoAttachmentsIsSentUnchanged() {
        let query = WeeAppModel.buildQuery(prompt: "Add all of this up.", uploadedFilePaths: [])
        XCTAssertEqual(query, "Add all of this up.")
    }

    func test_promptWithTextAndAttachmentIncludesTheFilePath() {
        let query = WeeAppModel.buildQuery(
            prompt: "Add all of this up.",
            uploadedFilePaths: ["/tmp/webui_uploads/abc123/screenshot.png"]
        )
        XCTAssertTrue(query.hasPrefix("Add all of this up."))
        XCTAssertTrue(
            query.contains("/tmp/webui_uploads/abc123/screenshot.png"),
            "the agent has no other way to find the attachment -- its path must be in the query"
        )
    }

    func test_emptyPromptWithAttachmentStillReferencesTheFilePath() {
        let query = WeeAppModel.buildQuery(
            prompt: "",
            uploadedFilePaths: ["/tmp/webui_uploads/abc123/screenshot.png"]
        )
        XCTAssertTrue(query.contains("/tmp/webui_uploads/abc123/screenshot.png"))
    }

    func test_multipleAttachmentsAreAllReferenced() {
        let query = WeeAppModel.buildQuery(
            prompt: "Compare these.",
            uploadedFilePaths: [
                "/tmp/webui_uploads/abc123/one.png",
                "/tmp/webui_uploads/abc123/two.png",
            ]
        )
        XCTAssertTrue(query.contains("/tmp/webui_uploads/abc123/one.png"))
        XCTAssertTrue(query.contains("/tmp/webui_uploads/abc123/two.png"))
    }

    func test_uploadResponseDecodesTheFilePathTheServerActuallyReturns() throws {
        // The real /upload endpoint's response body -- see agent_manager.py's
        // upload_file(). UploadResponse previously had no field for
        // "file_path" at all, so it was silently dropped during decoding.
        let json = """
        {"file_path": "/tmp/webui_uploads/abc123/screenshot.png", "filename": "screenshot.png", "size": 1234, "mime_type": "image/png"}
        """
        let response = try JSONDecoder().decode(UploadResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.filePath, "/tmp/webui_uploads/abc123/screenshot.png")
    }
}
