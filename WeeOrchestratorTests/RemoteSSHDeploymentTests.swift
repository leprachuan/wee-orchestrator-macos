import XCTest
@testable import WeeOrchestrator

@MainActor
final class RemoteSSHDeploymentTests: XCTestCase {
    /// Issue #21: install/update must not shell out to `ssh` with missing
    /// required fields — that would hang or fail confusingly with a raw
    /// process error instead of a clear validation message.
    func test_installRequiresHost() async {
        let model = WeeAppModel()
        model.remoteSSHHost = ""
        model.remoteSSHRepositoryURL = "https://example.com/repo.git"
        model.remoteSSHCheckoutDirectory = "/opt/app"

        await model.installRemoteAPIOverSSH()

        XCTAssertEqual(model.remoteSSHStatus, "Remote host is required")
        XCTAssertFalse(model.isRemoteSSHWorking)
    }

    func test_installRequiresRepository() async {
        let model = WeeAppModel()
        model.remoteSSHHost = "user@example.com"
        model.remoteSSHRepositoryURL = ""
        model.remoteSSHCheckoutDirectory = "/opt/app"

        await model.installRemoteAPIOverSSH()

        XCTAssertEqual(model.remoteSSHStatus, "Repository URL is required")
    }

    func test_installRequiresDirectory() async {
        let model = WeeAppModel()
        model.remoteSSHHost = "user@example.com"
        model.remoteSSHRepositoryURL = "https://example.com/repo.git"
        model.remoteSSHCheckoutDirectory = ""

        await model.installRemoteAPIOverSSH()

        XCTAssertEqual(model.remoteSSHStatus, "Remote install directory is required")
    }

    func test_updateRequiresHostAndDirectory() async {
        let model = WeeAppModel()
        model.remoteSSHHost = ""
        model.remoteSSHCheckoutDirectory = ""

        await model.updateRemoteAPIOverSSH()
        XCTAssertEqual(model.remoteSSHStatus, "Remote host is required")

        model.remoteSSHHost = "user@example.com"
        await model.updateRemoteAPIOverSSH()
        XCTAssertEqual(model.remoteSSHStatus, "Remote install directory is required")
    }
}
