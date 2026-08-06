import XCTest
@testable import WeeOrchestrator

final class FileBrowserPathTests: XCTestCase {
    // MARK: - components

    func test_componentsOfRootIsEmpty() {
        XCTAssertEqual(FileBrowserPath.components(for: ""), [])
    }

    func test_componentsSplitsOnSlash() {
        XCTAssertEqual(FileBrowserPath.components(for: "src/utils"), ["src", "utils"])
    }

    // MARK: - parent

    func test_parentOfTopLevelDirectoryIsRoot() {
        XCTAssertEqual(FileBrowserPath.parent(of: "src"), "")
    }

    func test_parentOfNestedDirectoryDropsLastComponent() {
        XCTAssertEqual(FileBrowserPath.parent(of: "src/utils/helpers"), "src/utils")
    }

    // MARK: - joined

    func test_joinedAtRootIsJustTheName() {
        XCTAssertEqual(FileBrowserPath.joined("", "src"), "src")
    }

    func test_joinedAppendsWithSlash() {
        XCTAssertEqual(FileBrowserPath.joined("src", "utils"), "src/utils")
    }

    // MARK: - breadcrumbTarget

    func test_breadcrumbTargetAtFirstIndexIsFirstComponentOnly() {
        XCTAssertEqual(FileBrowserPath.breadcrumbTarget(from: "src/utils/helpers", upTo: 0), "src")
    }

    func test_breadcrumbTargetAtMiddleIndexIncludesUpToThatComponent() {
        XCTAssertEqual(FileBrowserPath.breadcrumbTarget(from: "src/utils/helpers", upTo: 1), "src/utils")
    }

    func test_breadcrumbTargetAtLastIndexIsTheFullPath() {
        XCTAssertEqual(FileBrowserPath.breadcrumbTarget(from: "src/utils/helpers", upTo: 2), "src/utils/helpers")
    }

    // MARK: - absolute

    func test_absoluteJoinsRootWithoutTrailingSlash() {
        XCTAssertEqual(FileBrowserPath.absolute(root: "/opt/agent", relative: "src/main.py"), "/opt/agent/src/main.py")
    }

    func test_absoluteJoinsRootWithTrailingSlashWithoutDoubling() {
        XCTAssertEqual(FileBrowserPath.absolute(root: "/opt/agent/", relative: "src/main.py"), "/opt/agent/src/main.py")
    }

    func test_absoluteAtRootWithEmptyRelativeIsJustTheRoot() {
        XCTAssertEqual(FileBrowserPath.absolute(root: "/opt/agent", relative: "README.md"), "/opt/agent/README.md")
    }
}

final class AgentFileModelTests: XCTestCase {
    func test_decodesDirectoryEntryWithNilSize() throws {
        let json = #"{"name": "src", "isDirectory": true, "size": null, "modifiedAt": "2026-08-06T00:00:00+00:00"}"#
            .data(using: .utf8)!
        let entry = try JSONDecoder().decode(AgentFileEntry.self, from: json)
        XCTAssertTrue(entry.isDirectory)
        XCTAssertNil(entry.size)
        XCTAssertEqual(entry.id, "src")
    }

    func test_decodesFileEntryWithSize() throws {
        let json = #"{"name": "README.md", "isDirectory": false, "size": 42, "modifiedAt": "2026-08-06T00:00:00+00:00"}"#
            .data(using: .utf8)!
        let entry = try JSONDecoder().decode(AgentFileEntry.self, from: json)
        XCTAssertFalse(entry.isDirectory)
        XCTAssertEqual(entry.size, 42)
    }

    func test_decodesListResponse() throws {
        let json = ##"""
        {"agent": "test-agent", "path": "src", "entries": [
            {"name": "main.py", "isDirectory": false, "size": 100, "modifiedAt": null}
        ]}
        """##.data(using: .utf8)!
        let response = try JSONDecoder().decode(AgentFileListResponse.self, from: json)
        XCTAssertEqual(response.agent, "test-agent")
        XCTAssertEqual(response.path, "src")
        XCTAssertEqual(response.entries.count, 1)
    }

    func test_decodesFileViewResponse() throws {
        let json = ##"""
        {"path": "/opt/agent/README.md", "name": "README.md", "size": 42, "mime": "text/markdown", "language": "markdown", "content": "# Hello", "type": "text"}
        """##.data(using: .utf8)!
        let response = try JSONDecoder().decode(FileViewResponse.self, from: json)
        XCTAssertEqual(response.language, "markdown")
        XCTAssertEqual(response.content, "# Hello")
    }
}
