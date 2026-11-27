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

        game.scoreEveryCategory(count) { self.attachScreenshot(app, "05-scoring") }
        game.waitForRoundResults(rows: 4)
        // Taken at the top. Scrolling the host's rules card into view was worse: both standings cards then
        // run under the status bar, and the menu button covers the points.
        attachScreenshot(app, "06-results")

        game.endGameFromResults()
        attachScreenshot(app, "07-game-over")
    }
}
