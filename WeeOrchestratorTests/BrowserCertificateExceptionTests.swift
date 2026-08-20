import XCTest
import Security
@testable import WeeOrchestrator

/// Issue #68: per-session untrusted certificate exceptions in the embedded
/// browser. These tests exercise the trust/cancel decision and its scoping
/// directly against `BrowserSessionController`, without driving a real
/// WebKit certificate challenge.
@MainActor
final class BrowserCertificateExceptionTests: XCTestCase {
    /// DER bytes for a disposable, locally generated self-signed certificate
    /// (CN=wee-test-fixture.invalid). It has no corresponding private key
    /// anywhere and is not used by any real service — it exists only so
    /// `SecTrustCreateWithCertificates` has a structurally valid certificate
    /// to wrap; these tests never evaluate the trust, so its validity is
    /// irrelevant.
    private static let testCertificateBase64 = """
    MIIDJzCCAg+gAwIBAgIUb6NiIRKOM8GpceBArbLh9Giqpt4wDQYJKoZIhvcNAQEL\
    BQAwIzEhMB8GA1UEAwwYd2VlLXRlc3QtZml4dHVyZS5pbnZhbGlkMB4XDTI2MDgy\
    MDIzMjYxNVoXDTM2MDgxNzIzMjYxNVowIzEhMB8GA1UEAwwYd2VlLXRlc3QtZml4\
    dHVyZS5pbnZhbGlkMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqNUK\
    jHGZW85eI8d3iHI2xNvBbqX8iCKDuhyDu76oLIAs8cGuaCUekkJi3s6OWM14cHZL\
    T/3IFooCtHpO2HG+MbqK6IXZxCXtTAn8F44LPYUo+cym28AFdbgT3+/BZiNIHZVH\
    /zLXOCwy06bVOEoRFkcZIwN70ew6lUVlHC5V6/vQUPzOe8Z4yiRdonxsv0A1cPUR\
    jRFpTrOQ1Ka5FNKdum5YmZxpgP6y3zSmQsOGhsLFY6Cmp4vB3sakhB6siHnds03o\
    ZYm7FAZMilFl3361d8wLVw9qZDVJ/4+dFWHhW72Kx7pwmXUXpB64hevl6UWwDM4n\
    trFiNglj0zZVNt9kuwIDAQABo1MwUTAdBgNVHQ4EFgQUYKOlZ6N4WSr4XmT5LUWH\
    VYA3gy0wHwYDVR0jBBgwFoAUYKOlZ6N4WSr4XmT5LUWHVYA3gy0wDwYDVR0TAQH/\
    BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAjYnXb2ivYQ7HvZ5maP3rhoaMJooe\
    xBY1Nk22FwWFKmNhiPDNPwNVGAj7s8vMdq8PEWrC0MUVy0bbvDip3EQ35ALi2DaQ\
    3WDL8OK4vRcFS70Ky7QjjSIab7XhPVSyDlF+5vKKcCNbAKdorJXy/Esg5N4gqU8F\
    vekNSpc/gxlNoVpkXMuOdYU3hQG0ES+9SrpTHiMkHZbFditpimLKvixdheZNO7hI\
    kO7pWq3POrnr/JP2m7gi3HNOm+HWuJlQ1V24kA5iGIsxemZtfPlcXw38+0hxej+u\
    5aw70GgvHPsQiLM7NppMAMGUdrLRuljQS+ugUd7ZZmq3XzwSjmQvb8WpbA==
    """

    private func makeServerTrust() -> SecTrust {
        let data = Data(base64Encoded: Self.testCertificateBase64)!
        let certificate = SecCertificateCreateWithData(nil, data as CFData)!
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        precondition(status == errSecSuccess, "Failed to build a test SecTrust fixture")
        return trust!
    }

    private func makeController() -> BrowserSessionController {
        BrowserSessionController(
            sessionKey: "test-session",
            sessionID: "test-session-id",
            client: WeeAPIClient(configuration: .defaults)
        )
    }

    func test_defaultBehaviorHasNoTrustedHostsOrPendingChallenge() {
        let controller = makeController()
        XCTAssertTrue(controller.trustedCertificateHosts.isEmpty)
        XCTAssertNil(controller.pendingCertificateChallenge)
        XCTAssertFalse(controller.isActiveTabUnderCertificateException)
    }

    func test_trustingAPendingChallengeGrantsTheCredentialAndRecordsTheHost() {
        let controller = makeController()
        var receivedDisposition: URLSession.AuthChallengeDisposition?
        var receivedCredential: URLCredential?
        controller.pendingCertificateChallenge = PendingCertificateChallenge(
            host: "dev.example",
            serverTrust: makeServerTrust(),
            completionHandler: { disposition, credential in
                receivedDisposition = disposition
                receivedCredential = credential
            }
        )

        controller.trustPendingCertificate()

        XCTAssertEqual(receivedDisposition, .useCredential)
        XCTAssertNotNil(receivedCredential)
        XCTAssertTrue(controller.trustedCertificateHosts.contains("dev.example"))
        XCTAssertNil(controller.pendingCertificateChallenge, "the resolved challenge should be cleared")
    }

    func test_cancelingAPendingChallengeBlocksTheNavigationAndTrustsNothing() {
        let controller = makeController()
        var receivedDisposition: URLSession.AuthChallengeDisposition?
        controller.pendingCertificateChallenge = PendingCertificateChallenge(
            host: "dev.example",
            serverTrust: makeServerTrust(),
            completionHandler: { disposition, _ in receivedDisposition = disposition }
        )

        controller.cancelPendingCertificate()

        XCTAssertEqual(receivedDisposition, .cancelAuthenticationChallenge)
        XCTAssertTrue(controller.trustedCertificateHosts.isEmpty)
        XCTAssertNil(controller.pendingCertificateChallenge)
    }

    func test_trustingOneHostDoesNotTrustAnUnrelatedHost() {
        let controller = makeController()
        controller.pendingCertificateChallenge = PendingCertificateChallenge(
            host: "trusted.example",
            serverTrust: makeServerTrust(),
            completionHandler: { _, _ in }
        )
        controller.trustPendingCertificate()

        XCTAssertTrue(controller.trustedCertificateHosts.contains("trusted.example"))
        XCTAssertFalse(controller.trustedCertificateHosts.contains("other.example"))
    }

    func test_certificateExceptionDoesNotLeakToANewSession() {
        let first = makeController()
        first.pendingCertificateChallenge = PendingCertificateChallenge(
            host: "dev.example",
            serverTrust: makeServerTrust(),
            completionHandler: { _, _ in }
        )
        first.trustPendingCertificate()
        XCTAssertTrue(first.trustedCertificateHosts.contains("dev.example"))

        let second = makeController()
        XCTAssertTrue(second.trustedCertificateHosts.isEmpty)
    }

    func test_isActiveTabUnderCertificateExceptionReflectsTheAddressBarHost() {
        let controller = makeController()
        controller.address = "https://dev.example/path"
        XCTAssertFalse(controller.isActiveTabUnderCertificateException)

        controller.trustedCertificateHosts.insert("dev.example")
        XCTAssertTrue(controller.isActiveTabUnderCertificateException)

        controller.address = "https://elsewhere.example/path"
        XCTAssertFalse(controller.isActiveTabUnderCertificateException)
    }
}
