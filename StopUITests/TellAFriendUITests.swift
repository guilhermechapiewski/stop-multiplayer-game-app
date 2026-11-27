import XCTest

/// Settings → Tell a friend shows the QR code and the share link.
/// With TEST_RUNNER_STOP_TELL_A_FRIEND_SHOT=<path.png>, also saves a screenshot of the screen there.
final class TellAFriendUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testTellAFriendShowsQRCodeAndShareLink() throws {
        let environment = ProcessInfo.processInfo.environment
        let portuguese = environment["STOP_TELL_A_FRIEND_LANG"]?.hasPrefix("pt") == true
        let app = launchApp(["-uiTesting", "-playerName", "Gui"] + (portuguese ? UITest.portuguese : []))

        waitFor(app.buttons["settingsButton"]).tap()
        waitFor(app.buttons["tellAFriendLink"]).tap()
        let qrCode = waitFor(app.images["tellAFriendQRCode"])
        XCTAssertEqual(qrCode.label, portuguese ? "QR code da página do app na App Store"
                                                : "QR code for the App Store page")
        waitUntilEnabled(app.buttons["tellAFriendShareLink"])
        attachScreenshot(app, "tell-a-friend")

        if let path = environment["STOP_TELL_A_FRIEND_SHOT"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
    }
}
