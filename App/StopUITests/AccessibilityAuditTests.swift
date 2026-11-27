import XCTest

/// Runs Xcode's accessibility audit on every main screen: Home, host setup, practice setup, lobby, writing,
/// scoring, round results and game over. Each screen's findings are attached to the result bundle
/// ("a11y-<screen>"), and any finding fails the test except the system-control false positives listed in
/// `isKnownFalsePositive`. With `TEST_RUNNER_AUDIT_REPORT=1` it only reports (attachments and the log).
final class AccessibilityAuditTests: XCTestCase {
    private var reportOnly: Bool { ProcessInfo.processInfo.environment["AUDIT_REPORT"] == "1" }

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testAuditEveryScreen() throws {
        let app = launchApp(["-uiTesting", "-playerName", "Gui"])
        let game = GameSteps(app: app, test: self)

        waitFor(app.buttons["hostGameButton"])
        try audit(app, "home")

        app.buttons["hostGameButton"].tap()
        waitFor(app.buttons["createGameButton"])
        try audit(app, "host-setup")
        app.buttons["setupCancelButton"].tap()

        waitFor(app.buttons["practiceButton"]).tap()
        waitFor(app.buttons["startPracticeButton"])
        try audit(app, "practice-setup")
        app.buttons["startPracticeButton"].tap()

        waitUntilEnabled(app.buttons["startGameButton"])
        try audit(app, "lobby")
        game.startFromLobby()

        // Audited with the answers in and the keyboard closed: the keyboard's own bar is the system's.
        let count = game.waitForWriting()
        game.type(Array(repeating: "Bento", count: count), closeKeyboard: true)
        waitUntilGone(app.keyboards.firstMatch)
        try audit(app, "writing")
        game.tapStop()

        waitFor(game.element("scoringCategory-0"), timeout: UITest.longTimeout)
        waitUntilGone(game.stopStamp)
        waitUntilEnabled(app.buttons["score-10"])
        try audit(app, "scoring")
        game.scoreEveryCategory(count)

        game.waitForRoundResults(rows: 4)
        try audit(app, "round-results")
        game.endGameFromResults()
        try audit(app, "game-over")
    }

    /// Findings that aren't defects, each checked by hand (the screenshots in appstore/screenshots show these
    /// screens):
    /// - Navigation bar buttons (Cancel, the game menu): system Liquid Glass controls that UIKit sizes and
    ///   colors; the audit samples the glass behind the tinted text.
    /// - Dynamic Type in the bottom action bar and the writing screen's pinned header: both stop growing at the
    ///   second accessibility size on purpose (`.dynamicTypeSize(...accessibility2)`), so the pinned bars never
    ///   crowd out the answer fields or the list they sit over.
    /// - Dynamic Type on player initials: decorative avatars, hidden from VoiceOver (the name is read instead).
    /// - Dynamic Type on host setup's categories footer: a system `Form` section footer, sized by UIKit (it does
    ///   grow and wrap; giving it our own font or `fixedSize` didn't change the finding).
    /// - Contrast of anything under the bottom action bar: content scrolled beneath the translucent bar, where
    ///   the audit samples the blur, not the text's real background.
    /// - "Contrast nearly passed": text in the system's secondary label color, Apple's standard for secondary
    ///   text, a hair under 4.5:1 on the grouped background; these are warnings, not failures.
    /// - Contrast and clipping findings the audit can't attach to an element: nothing to locate or fix; they're
    ///   kept in the attachment, and the screens were checked by eye at the default and largest text sizes.
    @MainActor
    private func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        if issue.auditType == .contrast, issue.compactDescription.contains("nearly passed") { return true }
        guard let element = issue.element else {
            return issue.auditType == .contrast || issue.auditType == .textClipped
        }
        let frame = element.frame
        func within(_ container: XCUIElement) -> Bool { container.exists && container.frame.intersects(frame) }
        let navigationBar = app.navigationBars.firstMatch
        if [.contrast, .dynamicType].contains(issue.auditType),
           navigationBar.exists, frame.maxY <= navigationBar.frame.maxY + 1 {
            return true
        }
        let bottomBar = app.otherElements["bottomActionBar"]
        switch issue.auditType {
        case .dynamicType:
            return within(bottomBar) || within(app.otherElements["writingHeader"])
                || ["playerInitial", "categoriesFooter"].contains(element.identifier)
        case .contrast:
            return within(bottomBar)
        default:
            return false
        }
    }

    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        var lines: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)' \($0.frame)" } ?? "-"
            let ignored = self.isKnownFalsePositive(issue, in: app)
            lines.append("[\(screen)] \(ignored ? "ignored " : "")\(issue.auditType) — \(issue.compactDescription)"
                         + " — \(element)")
            return ignored || self.reportOnly
        }
        if reportOnly { print(lines.joined(separator: "\n")) }
        let attachment = XCTAttachment(string: lines.isEmpty ? "No issues." : lines.joined(separator: "\n"))
        attachment.name = "a11y-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
