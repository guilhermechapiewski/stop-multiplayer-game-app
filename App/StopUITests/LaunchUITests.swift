import XCTest

/// Smoke test of the launch flow: onboarding → Home → Settings → About.
final class LaunchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testOnboardingThenHomeSettingsAbout() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let field = app.textFields["nameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let continueButton = app.buttons["continueButton"]
        XCTAssertFalse(continueButton.isEnabled)
        field.typeText("Gui")
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        XCTAssertTrue(app.buttons["hostGameButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["joinGameButton"].exists)
        XCTAssertTrue(app.buttons["practiceButton"].exists)

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.textFields["settingsNameField"].waitForExistence(timeout: 5))
        app.buttons["aboutLink"].tap()
        XCTAssertTrue(app.staticTexts["appVersion"].waitForExistence(timeout: 5))
    }
}
