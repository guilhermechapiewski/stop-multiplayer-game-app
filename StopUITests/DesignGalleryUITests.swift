import XCTest

/// Design previews: a screenshot of every screen, saved to `GALLERY_DIR` as `NN-name.png` for side-by-side
/// review (`tools/design_gallery.sh` runs it in each appearance, language and text size). Skipped unless
/// `GALLERY_DIR` is set (passed as `TEST_RUNNER_GALLERY_DIR`); `GALLERY_LANG=pt-BR` switches to Portuguese.
/// Each test covers one part of the app, so a screen that can't be reached (say, at the largest text size)
/// costs only its own shots.
final class DesignGalleryUITests: XCTestCase {
    private var directory: URL!
    private var language: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["GALLERY_DIR"], !path.isEmpty else { throw XCTSkip("GALLERY_DIR not set") }
        directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        language = environment["GALLERY_LANG"]?.hasPrefix("pt") == true
            ? UITest.portuguese : ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        launchApp(["-uiTesting"] + arguments + language)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Swipes up until `element` can be tapped (at accessibility text sizes rows start off screen).
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        return waitFor(element, "hittable == true")
    }

    // MARK: Menus

    @MainActor
    func test1Menus() {
        var app = launch([])
        waitFor(app.textFields["nameField"])
        capture(app, "01-onboarding")
        app.terminate()

        app = launch(["-playerName", "Sam"])
        waitFor(app.buttons["hostGameButton"])
        capture(app, "02-home")

        app.buttons["settingsButton"].tap()
        waitFor(app.switches["soundsToggle"])
        capture(app, "03-settings")
        scrollTo(app.buttons["tellAFriendLink"], in: app).tap()
        waitFor(app.descendants(matching: .any)["tellAFriendQRCode"])
        capture(app, "04-tell-a-friend")
        app.terminate()

        app = launch(["-playerName", "Sam"])
        waitFor(app.buttons["settingsButton"]).tap()
        scrollTo(app.buttons["aboutLink"], in: app).tap()
        waitFor(app.staticTexts["appVersion"])
        capture(app, "05-about")
        app.terminate()

        app = launch(["-playerName", "Sam", "-demoEndNotice", "removed"])
        waitFor(app.alerts.firstMatch)
        capture(app, "06-ended-alert")
    }

    // MARK: Setup and join

    @MainActor
    func test2Setup() {
        var app = launch(["-playerName", "Sam", "-openRoute", "hostSetup"])
        waitFor(app.buttons["createGameButton"])
        capture(app, "07-host-setup")
        let info = app.buttons["silentModeInfoButton"]
        for _ in 0..<8 where !info.isHittable { app.swipeUp() }
        capture(app, "08-host-setup-rules")
        info.tap()
        waitFor(app.descendants(matching: .any)["silentModeInfo"])
        capture(app, "09-silent-mode-info")
        app.terminate()

        app = launch(["-playerName", "Sam", "-openRoute", "join"])
        waitFor(app.descendants(matching: .any)["searchingForGames"])
        capture(app, "10-join-searching")
        app.terminate()

        app = launch(["-playerName", "Sam", "-openRoute", "join", "-demoGames"])
        waitFor(app.buttons["game-Ana"])
        capture(app, "11-join-games")
        app.terminate()

        app = launch(["-playerName", "Sam", "-openRoute", "practiceSetup"])
        waitFor(app.buttons["startPracticeButton"])
        capture(app, "12-practice-setup")
    }

    // MARK: A round

    @MainActor
    func test3Round() {
        let pt = language == UITest.portuguese
        let answers = pt
            ? ["Carla", "Cavalo", "Caju", "Cinza", "Curitiba", "Caneta", "Casas Bahia", "Cozinheira", "Coxinha",
               "Central do Brasil", "Cotovelo", "Chata"]
            : ["Clara", "Camel", "Cherry", "Crimson", "Chicago", "Candle", "Crayola", "Chef", "Curry",
               "Casablanca", "Chin", "Colander"]
        let app = launch(["-mockGame", "-mockSeed", "3", "-playerName", pt ? "Lia" : "Sam"])
        let game = GameSteps(app: app, test: self)

        waitUntilEnabled(app.buttons["startGameButton"])
        capture(app, "13-lobby")
        game.startFromLobby()
        waitFor(game.element("revealedLetter"))
        capture(app, "14-letter-reveal")
        waitFor(app.staticTexts["countdownNumber"])
        capture(app, "15-countdown")

        let count = game.waitForWriting()
        capture(app, "16-writing-empty")
        game.type(Array(answers.prefix(count)), closeKeyboard: true)
        waitUntilGone(app.keyboards.firstMatch)
        let first = app.textFields["answerField-0"]
        for _ in 0..<4 where !first.isHittable { app.swipeDown() }
        capture(app, "17-writing")

        game.tapStop()
        waitFor(game.stopStamp)
        capture(app, "18-stop-stamp")

        waitFor(game.element("scoringCategory-0"), timeout: UITest.longTimeout)
        waitUntilGone(game.stopStamp)
        let bia = app.otherElements.matching(NSPredicate(format: "identifier == 'answerRow' AND label == 'Bia'"))
            .firstMatch
        waitFor(bia, timeout: UITest.longTimeout)
        capture(app, "20-scoring-read-aloud")

        for category in 0..<count {
            waitFor(game.element("scoringCategory-\(category)"), timeout: UITest.longTimeout)
            waitUntilEnabled(app.buttons["score-10"]).tap()
            let next = waitUntilEnabled(app.buttons["nextCategoryButton"], timeout: UITest.longTimeout)
            if category == 0 { capture(app, "21-scoring-completed") }
            if category == 1 { capture(app, "22-scoring-previous-next") }
            next.tap()
        }

        game.waitForRoundResults(rows: 4)
        capture(app, "23-round-results")
        app.swipeUp()
        app.swipeUp()
        capture(app, "24-round-results-rules")
        game.endGameFromResults()
        capture(app, "25-game-over")
    }

    // MARK: Status screens

    @MainActor
    func test4Status() {
        let shots: [(kind: String, name: String, wait: String)] = [
            ("collecting", "19-collecting", "continueAnywayButton"),
            ("hostAway", "26-host-away", "hostAwayOverlay"),
            ("mayBeGone", "27-host-may-be-gone", "hostGoneLeaveButton"),
            ("writingAway", "28-host-away-writing", "hostAwayBanner"),
            ("banner", "29-presence-banner", "presenceBanner"),
            ("ended", "30-game-ended", "backHomeButton"),
            ("rejoining", "31-rejoining", "cancelRejoinButton"),
            ("rejoiningGone", "32-rejoining-host-gone", "cancelRejoinButton"),
        ]
        // A shot whose marker doesn't turn up is still taken (and noted), so one stubborn screen doesn't cost
        // the rest.
        var missing: [String] = []
        for shot in shots {
            let app = launch(["-playerName", "Sam", "-demoPresence", shot.kind])
            if !app.descendants(matching: .any)[shot.wait].waitForExistence(timeout: UITest.timeout) {
                missing.append(shot.name)
            }
            capture(app, shot.name)
            app.terminate()
        }
        XCTAssertEqual(missing, [], "screens without their marker")
    }
}
