import XCTest

/// Practice with bots: setup → lobby with the bots → End practice; and a full round against fast bots.
final class PracticeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSetupToLobbyThenEndPractice() {
        let app = launch()

        app.buttons["startPracticeButton"].tap()
        waitUntilEnabled(app.buttons["startGameButton"])

        endPractice(app)
        waitFor(app.buttons["practiceButton"])
    }

    /// Home → Practice with bots → 2 fast bots → a full round → End practice → Home.
    @MainActor
    func testFullPracticeRoundEnglish() { playFullRound(fromHome: true, languageArguments: [], botPrefix: "Robo ") }

    @MainActor
    func testFullPracticeRoundPortuguese() {
        playFullRound(fromHome: false, languageArguments: UITest.portuguese, botPrefix: "Robô ")
    }

    // MARK: Full round

    /// Two stops end the round, so after the player's STOP a fast bot has to stop too: by then the bots have
    /// typed what they know, and scoring shows their real answers.
    @MainActor
    private func playFullRound(fromHome: Bool, languageArguments: [String], botPrefix: String) {
        let app = launch(languageArguments, fromHome: fromHome)
        let game = GameSteps(app: app, test: self)
        app.steppers["botsStepper"].buttons.element(boundBy: 0).tap()
        app.segmentedControls["botSpeedPicker"].buttons.element(boundBy: 2).tap()
        attachScreenshot(app, "1-setup")
        app.buttons["startPracticeButton"].tap()

        let start = waitUntilEnabled(app.buttons["startGameButton"])
        let players = game.lobbyPlayers
        XCTAssertEqual(players.count, 3)
        XCTAssertEqual(players.filter { $0.hasPrefix(botPrefix) }.count, 2, "\(players)")
        app.steppers["lobbyStopsStepper"].buttons.element(boundBy: 1).tap()
        attachScreenshot(app, "2-lobby")
        start.tap()

        let count = game.waitForWriting()
        game.type(Array(repeating: "Bento", count: count))
        attachScreenshot(app, "3-writing")
        // Two stops end this round: it locks once a bot stops too.
        game.tapStop(lockingRound: nil)
        if game.element("stoppedBanner").waitForExistence(timeout: 3) {
            attachScreenshot(app, "4-stopped")
        }
        game.expectRoundLocked(1, timeout: UITest.longTimeout)
        game.scoreEveryCategory(count) { self.attachScreenshot(app, "5-scoring") }
        game.waitForRoundResults(rows: 3)
        attachScreenshot(app, "6-round-results")
        endPractice(app)

        waitFor(game.element("winnerTitle"))
        attachScreenshot(app, "7-standings")
        app.buttons["backHomeButton"].tap()
        waitFor(app.buttons["practiceButton"])
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ extraArguments: [String] = [], fromHome: Bool = false) -> XCUIApplication {
        var arguments = ["-uiTesting", "-playerName", "Gui"] + extraArguments
        if !fromHome { arguments += ["-openRoute", "practiceSetup"] }
        let app = launchApp(arguments)
        if fromHome { waitFor(app.buttons["practiceButton"]).tap() }
        waitFor(app.buttons["startPracticeButton"])
        return app
    }

    @MainActor
    private func endPractice(_ app: XCUIApplication) {
        waitFor(app.buttons["gameMenu"], "hittable == true").tap()
        let item = waitFor(app.buttons["endPracticeMenuItem"])
        // Practice replaces the multiplayer actions.
        XCTAssertFalse(app.buttons["leaveGameMenuItem"].exists)
        XCTAssertFalse(app.buttons["endGameMenuItem"].exists)
        XCTAssertFalse(app.buttons["removePlayerMenuItem"].exists)
        item.tap()
        waitFor(app.alerts.buttons["confirmMenuActionButton"].firstMatch).tap()
    }
}
