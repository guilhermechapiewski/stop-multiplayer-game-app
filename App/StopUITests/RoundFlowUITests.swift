import XCTest

/// A one-round game against the mock-game bots: start → letter → countdown → write → STOP → scoring →
/// round results → end game → game over → Home.
final class RoundFlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testPlayGameAgainstBots() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockGame", "-playerName", "Gui"]
        app.launch()

        let start = app.buttons["startGameButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let ready = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        wait(for: [ready], timeout: 10)
        start.tap()

        XCTAssertTrue(app.staticTexts["revealedLetter"].waitForExistence(timeout: 5)
                      || app.otherElements["revealedLetter"].exists)
        snapshot(app, "1-reveal")
        XCTAssertTrue(app.staticTexts["countdownNumber"].waitForExistence(timeout: 5))
        snapshot(app, "2-countdown")

        let stop = app.buttons["stopButton"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertFalse(stop.isEnabled)
        let fields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'answerField-'"))
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5))
        let count = fields.count
        XCTAssertGreaterThan(count, 0)
        // The first field has focus; Return moves to the next one.
        for index in 0..<count {
            app.typeText(index == count - 1 ? "Bento" : "Bento\n")
        }
        snapshot(app, "3-writing")
        XCTAssertTrue(stop.isEnabled)
        stop.tap()

        // Score every category 10; the bots score themselves.
        for category in 1...count {
            let header = app.descendants(matching: .any)["scoringCategory-\(category - 1)"]
            XCTAssertTrue(header.waitForExistence(timeout: 15), "category \(category)")
            let ten = app.buttons["score-10"]
            let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: ten)
            wait(for: [enabled], timeout: 10)
            ten.tap()
            if category == 1 { snapshot(app, "4-scoring") }
            // The completed category shows for one host tick; catch it when we can.
            if category == 1, app.staticTexts["categoryCompleted"].waitForExistence(timeout: 3) {
                snapshot(app, "5-category-completed")
            }
        }

        let nextRound = app.buttons["nextRoundButton"]
        XCTAssertTrue(nextRound.waitForExistence(timeout: 15))
        snapshot(app, "6-round-results")
        app.buttons["endGameButton"].tap()
        let confirm = app.alerts.buttons["confirmEndGameButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(app.staticTexts["winnerTitle"].waitForExistence(timeout: 10)
                      || app.otherElements["winnerTitle"].exists)
        snapshot(app, "7-game-over")
        app.buttons["backHomeButton"].tap()
        XCTAssertTrue(app.buttons["hostGameButton"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
