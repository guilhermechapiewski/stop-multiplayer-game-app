import XCTest

/// Shared launch and wait helpers. Every wait is predicate-based with one generous timeout (the suite runs on
/// busy machines, where short waits tripped); there are no fixed sleeps.
enum UITest {
    static let timeout: TimeInterval = 30
    /// Waits on the bots: their stops, and their self-scores in each category.
    static let longTimeout: TimeInterval = 90

    /// `-mockGame` with a clean state: hosting straight away, with the bots Ana, Bia and Caio.
    static let mockGame = ["-uiTesting", "-mockGame", "-playerName", "Gui"]
    static let portuguese = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
}

extension XCTestCase {
    @MainActor
    func launchApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Waits until `element` matches `predicate` (an `NSPredicate` format over `XCUIElement` properties).
    @MainActor @discardableResult
    func waitFor(_ element: XCUIElement, _ predicate: String = "exists == true", timeout: TimeInterval = UITest.timeout,
              file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.description): not \(predicate) after \(Int(timeout)) s",
                       file: file, line: line)
        return element
    }

    @MainActor @discardableResult
    func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = UITest.timeout,
                          file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        waitFor(element, "exists == true AND isEnabled == true", timeout: timeout, file: file, line: line)
    }

    /// One query that returns when the element is gone (no polling loop of our own).
    @MainActor
    func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = UITest.timeout,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForNonExistence(timeout: timeout), "\(element.description) still on screen",
                      file: file, line: line)
    }

    @MainActor
    func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The steps of a game, as the host's player plays them.
@MainActor
struct GameSteps {
    let app: XCUIApplication
    let test: XCTestCase

    func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

    var answerFields: XCUIElementQuery {
        app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'answerField-'"))
    }

    /// Waits for the lobby's Start (enabled once the bots joined) and taps it.
    func startFromLobby() {
        test.waitUntilEnabled(app.buttons["startGameButton"]).tap()
    }

    /// Waits for writing (the reveal and countdown come first) and returns how many categories there are.
    @discardableResult
    func waitForWriting() -> Int {
        test.waitFor(app.buttons["stopButton"])
        test.waitFor(app.textFields["answerField-0"])
        return answerFields.count
    }

    /// Types `answers` from the first field on; Return moves to the next field (and closes the keyboard after
    /// the last one).
    func type(_ answers: [String], closeKeyboard: Bool = false) {
        let first = app.textFields["answerField-0"]
        test.waitFor(first, "hittable == true")
        first.tap()
        test.waitFor(app.keyboards.firstMatch)
        for (index, answer) in answers.enumerated() {
            let isLast = index == answers.count - 1
            app.typeText(isLast && !closeKeyboard ? answer : answer + "\n")
        }
    }

    /// The full-screen STOP! stamp shown as a round locks.
    var stopStamp: XCUIElement { app.otherElements["stopStamp"] }

    /// Under `-uiTesting` the game screen keeps an invisible marker whose value is the last locked round.
    var roundLockedMarker: XCUIElement { app.otherElements["roundLockedMarker"] }

    /// Checks that `round` locked (the STOP! stamp was shown for it), so a later wait for the stamp to go away
    /// can't pass without it ever having appeared.
    func expectRoundLocked(_ round: Int, timeout: TimeInterval = UITest.timeout,
                           file: StaticString = #filePath, line: UInt = #line) {
        test.waitFor(roundLockedMarker, "value == '\(round)'", timeout: timeout, file: file, line: line)
    }

    /// Taps STOP; when this stop locks the round (`lockingRound`), checks that it did.
    func tapStop(lockingRound round: Int? = 1, file: StaticString = #filePath, line: UInt = #line) {
        test.waitUntilEnabled(app.buttons["stopButton"], file: file, line: line).tap()
        if let round { expectRoundLocked(round, file: file, line: line) }
    }

    /// Scrolls up until `element` is clear of the bottom action bar (which covers the end of a scrolled screen).
    func scrollAboveBottomBar(_ element: XCUIElement) {
        let bar = app.otherElements["bottomActionBar"]
        for _ in 0..<4 where element.frame.maxY > bar.frame.minY - 8 { app.swipeUp() }
        XCTAssertLessThanOrEqual(element.frame.maxY, bar.frame.minY, "\(element) is under the bottom bar")
    }

    /// Scores every category with `points` and, as the host, taps Next category (See results after the last)
    /// once everyone has scored, waiting for each category to come up. The STOP! stamp covers the screen for a
    /// moment as scoring opens, and a tap then would be lost, so the first category waits for it to go.
    /// `beforeFirstTap` runs on the first category before scoring it; `firstCompleted` once it is complete,
    /// before moving on.
    func scoreEveryCategory(_ count: Int, points: Int = 10, beforeFirstTap: (() throws -> Void)? = nil,
                            firstCompleted: (() throws -> Void)? = nil) rethrows {
        for category in 0..<count {
            test.waitFor(element("scoringCategory-\(category)"), timeout: UITest.longTimeout)
            if category == 0 {
                test.waitUntilGone(stopStamp)
            }
            let button = test.waitUntilEnabled(app.buttons["score-\(points)"])
            if category == 0 { try beforeFirstTap?() }
            button.tap()
            let next = test.waitUntilEnabled(app.buttons["nextCategoryButton"], timeout: UITest.longTimeout)
            if category == 0 { try firstCompleted?() }
            next.tap()
        }
    }

    /// As the host, taps Next category through every category once it's complete (blank answers and the bots'
    /// self-scores complete them without a pick of the host's), up to the round results.
    func advanceEveryCategory(_ count: Int) {
        for category in 0..<count {
            test.waitFor(element("scoringCategory-\(category)"), timeout: UITest.longTimeout)
            test.waitUntilEnabled(app.buttons["nextCategoryButton"], timeout: UITest.longTimeout).tap()
        }
    }

    /// Waits for the round results (as the host: Next round is there) and checks the round's ranking rows.
    func waitForRoundResults(rows: Int, file: StaticString = #filePath, line: UInt = #line) {
        test.waitFor(app.buttons["nextRoundButton"], timeout: UITest.longTimeout, file: file, line: line)
        let standings = element("roundStandings").descendants(matching: .any).matching(identifier: "standingRow")
        XCTAssertEqual(standings.count, rows, "round result rows", file: file, line: line)
    }

    /// From the round results: End game (or End practice), confirm, and wait for the final standings.
    func endGameFromResults() {
        app.buttons["endGameButton"].tap()
        test.waitFor(app.alerts.buttons["confirmEndGameButton"].firstMatch).tap()
        test.waitFor(element("winnerTitle"))
    }

    /// Picks a game menu item and confirms it.
    func menu(_ item: String) {
        test.waitFor(app.buttons["gameMenu"], "hittable == true").tap()
        test.waitFor(app.buttons[item]).tap()
        test.waitFor(app.alerts.buttons["confirmMenuActionButton"].firstMatch).tap()
    }

    /// The names on the lobby's player chips.
    var lobbyPlayers: [String] {
        app.descendants(matching: .any).matching(identifier: "playerChip").allElementsBoundByIndex.map(\.label)
    }
}
