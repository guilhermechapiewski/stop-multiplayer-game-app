import XCTest

/// Practice with bots: setup → lobby with the bots → End practice; and a full round against fast bots.
final class PracticeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSetupToLobbyThenEndPractice() {
        let app = launch()

        app.buttons["startPracticeButton"].tap()
        let start = app.buttons["startGameButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        waitUntilEnabled(start)

        endPractice(app)
        XCTAssertTrue(app.buttons["practiceButton"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testFullPracticeRoundEnglish() { playFullRound(languageArguments: []) }

    @MainActor
    func testFullPracticeRoundPortuguese() {
        playFullRound(languageArguments: ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"])
    }

    // MARK: Full round

    /// Two stops end the round, so after the player's STOP a fast bot has to stop too: by then the bots have
    /// typed what they know, and scoring shows their real answers.
    @MainActor
    private func playFullRound(languageArguments: [String]) {
        let app = launch(languageArguments)
        app.segmentedControls["botSpeedPicker"].buttons.element(boundBy: 2).tap()
        snapshot(app, "1-setup")
        app.buttons["startPracticeButton"].tap()

        let start = app.buttons["startGameButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        waitUntilEnabled(start)
        app.steppers["lobbyStopsStepper"].buttons.element(boundBy: 1).tap()
        snapshot(app, "2-lobby")
        start.tap()

        XCTAssertTrue(app.staticTexts["countdownNumber"].waitForExistence(timeout: 10))
        snapshot(app, "3-countdown")

        let stop = app.buttons["stopButton"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        let fields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'answerField-'"))
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5))
        let count = fields.count
        for index in 0..<count {
            app.typeText(index == count - 1 ? "Bento" : "Bento\n")
        }
        snapshot(app, "4-writing")
        stop.tap()
        if app.descendants(matching: .any)["stoppedBanner"].waitForExistence(timeout: 3) {
            snapshot(app, "5-stopped")
        }

        for category in 0..<count {
            let header = app.descendants(matching: .any)["scoringCategory-\(category)"]
            XCTAssertTrue(header.waitForExistence(timeout: 60), "category \(category)")
            // The STOP! stamp covers the screen for a moment as scoring opens; a tap then would be lost.
            let stamp = app.descendants(matching: .any)["stopStamp"]
            let stampGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: stamp)
            wait(for: [stampGone], timeout: 10)
            let ten = app.buttons["score-10"]
            waitUntilEnabled(ten)
            snapshot(app, "6-scoring-\(category)")
            ten.tap()
        }

        XCTAssertTrue(app.buttons["nextRoundButton"].waitForExistence(timeout: 20))
        snapshot(app, "7-round-results")
        endPractice(app)

        XCTAssertTrue(app.descendants(matching: .any)["winnerTitle"].waitForExistence(timeout: 10))
        snapshot(app, "8-standings")
        app.buttons["backHomeButton"].tap()
        XCTAssertTrue(app.buttons["practiceButton"].waitForExistence(timeout: 10))
        snapshot(app, "9-home")
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-playerName", "Gui", "-openRoute", "practiceSetup"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["startPracticeButton"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func endPractice(_ app: XCUIApplication) {
        app.buttons["gameMenu"].tap()
        let item = app.buttons["endPracticeMenuItem"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        // Practice replaces the multiplayer actions.
        XCTAssertFalse(app.buttons["leaveGameMenuItem"].exists)
        XCTAssertFalse(app.buttons["endGameMenuItem"].exists)
        XCTAssertFalse(app.buttons["removePlayerMenuItem"].exists)
        item.tap()
        let confirm = app.alerts.buttons["confirmMenuActionButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement) {
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: 15)
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
