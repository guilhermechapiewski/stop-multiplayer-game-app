import XCTest

/// A tour of the main screens for visual review: saves a screenshot of each to `TOUR_DIR` and, with
/// `TOUR_AUDIT=1`, writes every accessibility audit issue to `TOUR_DIR/audit.txt`. Skipped unless `TOUR_DIR`
/// is set, e.g.:
///   xcrun simctl ui <sim> content_size accessibility-extra-extra-extra-large
///   TEST_RUNNER_TOUR_DIR=$PWD/build/tour TEST_RUNNER_TOUR_LANG=pt-BR xcodebuild test-without-building …
///     -only-testing:StopUITests/ScreenshotTourUITests
final class ScreenshotTourUITests: XCTestCase {
    /// One generous timeout for every wait: under load, accessibility snapshots can stall for seconds.
    private let timeout: TimeInterval = 30
    private var directory: URL!
    private var auditLog: [String] = []
    private var audits = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["TOUR_DIR"], !path.isEmpty else { throw XCTSkip("TOUR_DIR not set") }
        directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        audits = environment["TOUR_AUDIT"] == "1"
    }

    @MainActor
    func testTour() throws {
        let app = XCUIApplication()
        var arguments = ["-uiTesting", "-playerName", "Gui", "-openRoute", "practiceSetup"]
        if let language = ProcessInfo.processInfo.environment["TOUR_LANG"], language.hasPrefix("pt") {
            arguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        }
        app.launchArguments = arguments
        app.launch()

        let startPractice = app.buttons["startPracticeButton"]
        XCTAssertTrue(startPractice.waitForExistence(timeout: timeout))
        // Fast bots, so a bot's stop ends the round soon after mine.
        // (At accessibility text sizes the picker isn't segmented; the default speed does too.)
        let speed = app.segmentedControls["botSpeedPicker"]
        if speed.exists { speed.buttons.element(boundBy: 2).tap() }
        capture(app, "1-practice-setup")
        startPractice.tap()

        let start = app.buttons["startGameButton"]
        XCTAssertTrue(start.waitForExistence(timeout: timeout))
        waitUntilEnabled(start)
        capture(app, "2-lobby")
        start.tap()

        XCTAssertTrue(app.staticTexts["countdownNumber"].waitForExistence(timeout: timeout))
        capture(app, "3-countdown", audit: false)

        let stop = app.buttons["stopButton"]
        XCTAssertTrue(stop.waitForExistence(timeout: timeout))
        let fields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'answerField-'"))
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: timeout))
        capture(app, "4-writing-empty")
        let count = fields.count
        for index in 0..<count {
            app.typeText(index == count - 1 ? "Bento" : "Bento\n")
        }
        capture(app, "5-writing-filled", audit: false)
        // Scroll back to the top (the keyboard stays up), where the menu button meets the first field.
        app.swipeDown()
        app.swipeDown()
        capture(app, "6-writing-top", audit: false)
        stop.tap()
        if app.descendants(matching: .any)["stoppedBanner"].waitForExistence(timeout: 3) {
            capture(app, "7-stopped", audit: false)
        }

        for category in 0..<count {
            let header = app.descendants(matching: .any)["scoringCategory-\(category)"]
            // The first category waits for a bot to stop too.
            XCTAssertTrue(header.waitForExistence(timeout: 2 * timeout), "category \(category)")
            if category == 0 {
                // The STOP! stamp covers scoring for a moment; a tap then would be lost.
                XCTAssertTrue(app.otherElements["stopStamp"].waitForNonExistence(timeout: timeout))
            }
            let ten = app.buttons["score-10"]
            waitUntilEnabled(ten)
            if category == 0 { capture(app, "8-scoring") }
            ten.tap()
        }

        XCTAssertTrue(app.buttons["nextRoundButton"].waitForExistence(timeout: timeout))
        capture(app, "9-round-results")
        app.swipeUp()
        capture(app, "9b-round-results-scrolled", audit: false)
        app.buttons["endGameButton"].tap()
        let confirm = app.alerts.buttons["confirmEndGameButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        capture(app, "10-end-practice-alert", audit: false)
        confirm.tap()

        XCTAssertTrue(app.descendants(matching: .any)["winnerTitle"].waitForExistence(timeout: timeout))
        capture(app, "11-game-over")
        app.swipeUp()
        capture(app, "11b-game-over-scrolled", audit: false)
        app.buttons["backHomeButton"].tap()
        XCTAssertTrue(app.buttons["practiceButton"].waitForExistence(timeout: timeout))
        capture(app, "12-home")

        if audits {
            let text = auditLog.isEmpty ? "No issues.\n" : auditLog.joined(separator: "\n") + "\n"
            try text.write(to: directory.appendingPathComponent("audit.txt"), atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String, audit: Bool = true) {
        let png = app.screenshot().pngRepresentation
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
        guard audits, audit else { return }
        do {
            try app.performAccessibilityAudit { [weak self] issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)'" } ?? "-"
                self?.auditLog.append("\(name): \(issue.auditType) — \(issue.compactDescription) — \(element)")
                return true
            }
        } catch {
            auditLog.append("\(name): audit failed — \(error)")
        }
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement) {
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: timeout)
    }
}
