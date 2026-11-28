import XCTest

/// The App Store and website screenshots (`tools/screenshots.sh` runs this and frames the results). Skipped
/// unless `STOP_SCREENSHOTS=1` (passed as `TEST_RUNNER_STOP_SCREENSHOTS=1`); `STOP_SCREENSHOTS_LANG=pt-BR`
/// switches to Portuguese. The mock game is seeded (`-mockSeed`): the letter is always C, and the bots Ana,
/// Bia and Caio always type the same answers, so the shots are repeatable and hold no personal data.
final class ScreenshotTests: XCTestCase {
    /// Seed 3 draws the letter C first: easy to answer in both languages.
    private static let seed = "3"

    private struct Script {
        let arguments: [String]
        let playerName: String
        /// One answer per default category, all starting with C.
        let answers: [String]
    }

    private static let english = Script(
        arguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"], playerName: "Sam",
        answers: ["Clara", "Camel", "Cherry", "Crimson", "Chicago", "Candle", "Crayola", "Chef", "Curry",
                  "Casablanca", "Chin", "Colander"])
    private static let portuguese = Script(
        arguments: UITest.portuguese, playerName: "Lia",
        answers: ["Carla", "Cavalo", "Caju", "Cinza", "Curitiba", "Caneta", "Casas Bahia", "Cozinheira", "Coxinha",
                  "Central do Brasil", "Cotovelo", "Chata"])

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STOP_SCREENSHOTS"] == "1",
                          "Set TEST_RUNNER_STOP_SCREENSHOTS=1 (tools/screenshots.sh does)")
    }

    @MainActor
    func testScreenshots() {
        let script = ProcessInfo.processInfo.environment["STOP_SCREENSHOTS_LANG"]?.hasPrefix("pt") == true
            ? Self.portuguese : Self.english
        let app = launchApp(["-uiTesting", "-mockGame", "-mockSeed", Self.seed, "-playerName", script.playerName]
                            + script.arguments)
        let game = GameSteps(app: app, test: self)

        waitUntilEnabled(app.buttons["startGameButton"])
        attachScreenshot(app, "01-lobby")
        game.startFromLobby()

        waitFor(game.element("revealedLetter"))
        attachScreenshot(app, "02-letter")

        let count = game.waitForWriting()
        XCTAssertEqual(count, script.answers.count)
        game.type(script.answers, closeKeyboard: true)
        waitUntilGone(app.keyboards.firstMatch)
        // Back to the top: the letter and the first categories.
        let first = app.textFields["answerField-0"]
        for _ in 0..<4 where !first.isHittable { app.swipeDown() }
        waitFor(first, "hittable == true")
        attachScreenshot(app, "03-writing")

        game.tapStop()
        waitFor(game.stopStamp)
        attachScreenshot(app, "04-stop")

        // Read aloud (the default): the seeded bots score 5 s apart, so the shot has Ana's and Bia's answers
        // revealed with their points, Caio's still hidden, and the player's own answer waiting for a score.
        waitFor(game.element("scoringCategory-0"), timeout: UITest.longTimeout)
        waitUntilGone(game.stopStamp)
        let bia = app.otherElements.matching(NSPredicate(format: "identifier == 'answerRow' AND label == 'Bia'"))
            .firstMatch
        waitFor(bia, timeout: UITest.longTimeout)
        attachScreenshot(app, "05-scoring")
        XCTAssertTrue(app.otherElements.matching(NSPredicate(
            format: "identifier == 'answerRowHidden' AND label == 'Caio'")).firstMatch.exists,
                      "Caio scored before the shot: it should show one answer still hidden")

        game.scoreEveryCategory(count)
        game.waitForRoundResults(rows: 4)
        // Taken at the top. Scrolling the host's rules card into view was worse: both standings cards then
        // run under the status bar, and the menu button covers the points. When the bottom bar cuts into the
        // total standings, scroll up to show that card whole, or else to end it at a row's edge rather than
        // through a name, but no further than keeps the heading clear: the "Round 1 · Letter C" line below
        // the menu button's top, and the title below the button itself when it is wide enough to reach it.
        func text(_ english: String, _ portuguese: String) -> XCUIElement {
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
                                                 english, portuguese)).firstMatch
        }
        let line = text("Round 1", "Rodada 1").frame, title = text("Round results", "Resultado da rodada").frame
        let menu = game.element("gameMenu").frame
        let room = title.maxX > menu.minX - 8 ? title.minY - menu.maxY - 6 : line.minY - menu.minY
        let total = game.element("totalStandings")
        let barTop = app.buttons["nextRoundButton"].frame.minY - 16
        let edges = [total.frame.maxY + 20] + total.descendants(matching: .any).matching(identifier: "standingRow")
            .allElementsBoundByIndex.map { $0.frame.maxY + 1 }
        let scroll = edges.map { $0 - barTop }.filter { $0 <= room }.max() ?? 0
        if scroll > 4 {
            let start = game.element("roundStandings").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            // The first few points of a drag only start the pan (touch slop) and don't scroll.
            start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -scroll - 10)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
            Thread.sleep(forTimeInterval: 2) // let the scroll indicator fade
        }
        attachScreenshot(app, "06-results")

        game.endGameFromResults()
        attachScreenshot(app, "07-game-over")
    }
}
