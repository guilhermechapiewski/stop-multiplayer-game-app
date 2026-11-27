import XCTest

/// Games against the `-mockGame` bots (Ana, Bia and Caio), as the host: a full two-round game, a force-ended
/// round, and a relaunch that restores the draft.
final class RoundFlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Lobby → letter → countdown → write → STOP → scoring → round results → back to scoring, correct a score,
    /// results again → Next round with Give up allowed → give up → results → End game → game over → Home.
    @MainActor
    func testFullGameTwoRounds() {
        let app = launchApp(UITest.mockGame)
        let game = GameSteps(app: app, test: self)

        waitUntilEnabled(app.buttons["startGameButton"])
        XCTAssertEqual(game.lobbyPlayers.sorted(), ["Ana", "Bia", "Caio", "Gui"])
        game.startFromLobby()
        XCTAssertTrue(app.staticTexts["countdownNumber"].waitForExistence(timeout: UITest.timeout))
        attachScreenshot(app, "1-countdown")

        // The host re-rolls the letter during the countdown: the reveal starts over and lands on a new letter,
        // which the writing header then shows.
        waitFor(app.buttons["newLetterButton"], "hittable == true").tap()
        let revealed = waitFor(app.descendants(matching: .any)["revealedLetter"], timeout: UITest.longTimeout)
        let letterLabel = revealed.label
        XCTAssertTrue(letterLabel.hasPrefix("Letter "), letterLabel)

        // Round 1: fill every category and STOP. Give up starts off.
        let count = game.waitForWriting()
        XCTAssertTrue(game.element("writingHeader").staticTexts
                          .containing(NSPredicate(format: "label CONTAINS %@", letterLabel)).firstMatch.exists,
                      "the writing header shows the re-rolled \(letterLabel)")
        XCTAssertGreaterThan(count, 0)
        XCTAssertFalse(app.buttons["stopButton"].isEnabled)
        XCTAssertFalse(app.buttons["giveUpButton"].exists)
        game.type(Array(repeating: "Bento", count: count))
        attachScreenshot(app, "2-writing")
        game.tapStop()
        game.scoreEveryCategory(count) { self.attachScreenshot(app, "3-scoring") }
        game.waitForRoundResults(rows: 4)
        attachScreenshot(app, "4-round-results")
        XCTAssertEqual(game.roundPoints(of: "Gui"), "\(10 * count) points")

        // The host goes back from the results to the last category, then one more to the one before, and
        // changes their 10 there to a 5; going forward again, the round's total follows.
        XCTAssertGreaterThan(count, 1)
        waitFor(app.buttons["backToScoringButton"]).tap()
        waitFor(game.element("scoringCategory-\(count - 1)"))
        XCTAssertFalse(app.buttons["backToScoringButton"].exists)
        waitUntilEnabled(app.buttons["previousCategoryButton"]).tap()
        waitFor(game.element("scoringCategory-\(count - 2)"))
        waitUntilEnabled(app.buttons["score-5"]).tap()
        waitFor(app.buttons["score-5"], "isSelected == true")
        waitUntilEnabled(app.buttons["nextCategoryButton"]).tap()
        waitFor(game.element("scoringCategory-\(count - 1)"))
        waitUntilEnabled(app.buttons["nextCategoryButton"]).tap()
        game.waitForRoundResults(rows: 4)
        XCTAssertEqual(game.roundPoints(of: "Gui"), "\(10 * count - 5) points")

        // Round 2: allow giving up, then give up with blank answers (they score 0 on their own).
        // The rules card is at the bottom, under the Next round bar: scroll it into view first.
        let allowGiveUp = waitFor(app.switches["resultsAllowGiveUpToggle"])
        game.scrollAboveBottomBar(allowGiveUp)
        waitFor(allowGiveUp, "hittable == true")
        // The element spans the label too; its inner switch is the control.
        allowGiveUp.switches.firstMatch.tap()
        waitFor(allowGiveUp, "value == '1'")
        app.buttons["nextRoundButton"].tap()
        game.waitForWriting()
        waitFor(app.buttons["giveUpButton"], "hittable == true").tap()
        // A confirmation dialog (an action sheet), not an alert.
        waitFor(app.buttons["confirmGiveUpButton"].firstMatch).tap()
        game.expectRoundLocked(2)
        game.advanceEveryCategory(count)
        game.waitForRoundResults(rows: 4)

        game.endGameFromResults()
        XCTAssertEqual(game.element("finalStandings").descendants(matching: .any)
                           .matching(identifier: "standingRow").count, 4)
        attachScreenshot(app, "5-game-over")
        app.buttons["backHomeButton"].tap()
        waitFor(app.buttons["hostGameButton"])
    }

    /// The host ends the round from the game menu while everyone is still writing: scoring follows.
    @MainActor
    func testForceEndRound() {
        let app = launchApp(UITest.mockGame)
        let game = GameSteps(app: app, test: self)
        game.startFromLobby()
        game.waitForWriting()
        game.type(["Bento"], closeKeyboard: true)

        game.menu("forceEndRoundMenuItem")
        waitFor(game.element("scoringCategory-0"), timeout: UITest.longTimeout)
        // The first answer is Gui's own; the rest are blank (scored 0 on their own).
        waitUntilEnabled(app.buttons["score-10"])
    }

    /// The app is killed mid-writing: the relaunch comes back to the round with the typed answers in place.
    @MainActor
    func testRelaunchRestoresDraft() {
        // `-keepState`: `-uiTesting` alone wipes the store on every launch. `-resetState` wipes only this first one.
        let arguments = UITest.mockGame + ["-keepState"]
        let app = launchApp(arguments + ["-resetState"])
        let game = GameSteps(app: app, test: self)
        game.startFromLobby()
        game.waitForWriting()
        game.type(["Bento", "Baleia"])
        waitFor(app.textFields["answerField-1"], "value == 'Baleia'")

        // Like swiping the app away: it goes to the background first (which saves), then it's killed.
        XCUIDevice.shared.press(.home)
        waitFor(app, "state == \(XCUIApplication.State.runningBackgroundSuspended.rawValue)"
                    + " OR state == \(XCUIApplication.State.runningBackground.rawValue)")
        app.terminate()

        app.launchArguments = arguments
        app.launch()
        waitFor(app.textFields["answerField-0"], "value == 'Bento'")
        waitFor(app.textFields["answerField-1"], "value == 'Baleia'")
        XCTAssertTrue(app.buttons["stopButton"].exists)
    }
}
