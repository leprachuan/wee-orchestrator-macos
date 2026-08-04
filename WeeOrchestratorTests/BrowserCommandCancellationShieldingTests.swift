import XCTest
@testable import WeeOrchestrator

final class BrowserCommandCancellationShieldingTests: XCTestCase {
    /// Issue #56: iOS reported a remote browser-control command (navigating to snort.org)
    /// as canceled twice. Root cause: `BrowserSessionController.pollCommands()` dequeues a
    /// command, executes it, then submits its result — all inside the same poll-loop `Task`.
    /// If a concurrent `disconnect()` (e.g. the macOS user switching chat sessions, which
    /// disconnects every *other* session's controller) cancels that Task while a command is
    /// mid-execution, the command's result submission was interrupted too, so the server
    /// never got a definitive result and the remote (iOS) caller retried into the same race.
    ///
    /// The fix wraps the execute-then-submit step in its own unstructured `Task`, which —
    /// unlike a structured child task or `async let` — is not cancelled by the cancellation
    /// of the task that created it, so an already-dequeued command always gets a result
    /// submitted even if the surrounding poll loop is torn down mid-flight. This test proves
    /// that underlying concurrency guarantee directly, independent of networking/WebKit.
    func test_issue_56_unstructuredTaskSurvivesCancellationOfItsCreatingTask() async throws {
        final class Box: @unchecked Sendable {
            var completed = false
        }
        let box = Box()

        let outer = Task {
            // Mirrors pollCommands() being partway through an iteration (e.g. inside the
            // `pollNativeBrowserCommand` await) at the moment `disconnect()` cancels it.
            try await Task.sleep(for: .milliseconds(10))
            // Mirrors `try await Task { @MainActor in ... }.value` wrapping execute + submit.
            try await Task {
                try await Task.sleep(for: .milliseconds(80))
                box.completed = true
            }.value
        }

        try await Task.sleep(for: .milliseconds(30))
        outer.cancel()
        _ = try? await outer.value

        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(
            box.completed,
            "Cancelling the outer poll-loop task must not interrupt the unstructured inner task carrying out an already-dequeued command"
        )
    }

    /// Contrasts the fix against the bug it replaces: a *structured* child task (via a task
    /// group, which is what `async let` and `TaskGroup` children use under the hood) IS
    /// cancelled when its parent is cancelled — this is exactly the failure mode that made
    /// an in-flight command's result submission get interrupted before the fix.
    func test_issue_56_structuredChildTaskIsCancelledWithItsParent_contrastCase() async throws {
        final class Box: @unchecked Sendable {
            var completed = false
            var sawCancellation = false
        }
        let box = Box()

        let outer = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        try await Task.sleep(for: .milliseconds(80))
                        box.completed = true
                    } catch is CancellationError {
                        box.sawCancellation = true
                        throw CancellationError()
                    }
                }
                try await group.waitForAll()
            }
        }

        try await Task.sleep(for: .milliseconds(10))
        outer.cancel()
        _ = try? await outer.value

        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(box.completed, "A structured child task is expected to be interrupted by its parent's cancellation")
        XCTAssertTrue(box.sawCancellation)
    }
}
