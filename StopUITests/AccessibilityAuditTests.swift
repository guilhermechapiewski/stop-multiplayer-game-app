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
        try game.scoreEveryCategory(count, firstCompleted: { try self.audit(app, "scoring-completed") })

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
    /// - Contrast of content scrolled beneath the translucent bottom action bar (elements overlapping the bar
    ///   that aren't part of it): the audit samples the blur, not the text's real background. The bar's own
    ///   buttons and texts are checked like everything else.
    /// - "Contrast nearly passed": a warning-level finding (the audit's own "nearly"), excluded as a warning, not
    ///   a failure; it's on text in the system's secondary label color on the grouped background.
    /// - Contrast of the disabled scoring Next button (`nextCategoryButton`, until everyone has scored): WCAG
    ///   1.4.3 sets no contrast minimum for inactive controls, and the dimmed look is what says "not yet". Only
    ///   that button: any other disabled button is still checked.
    /// - Contrast findings the audit can't attach to an element (nothing to locate); they're kept in the
    ///   attachment. Element-less clipping findings still fail.
    @MainActor
    private func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        if issue.auditType == .contrast, issue.compactDescription.contains("nearly passed") { return true }
        guard let element = issue.element else { return issue.auditType == .contrast }
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
            return (within(bottomBar) && !isPart(element, of: bottomBar)) || isInDisabledNextButton(frame, in: app)
        default:
            return false
        }
    }

    /// Whether `frame` lies inside the scoring screen's Next button while it's disabled.
    @MainActor
    private func isInDisabledNextButton(_ frame: CGRect, in app: XCUIApplication) -> Bool {
        let next = app.buttons["nextCategoryButton"]
        return next.exists && !next.isEnabled && next.frame.contains(frame)
    }

    /// Whether `element` is one of `container`'s own descendants (same label and frame).
    @MainActor
    private func isPart(_ element: XCUIElement, of container: XCUIElement) -> Bool {
        let label = element.label, frame = element.frame
        return container.descendants(matching: .any).allElementsBoundByIndex
            .contains { $0.label == label && $0.frame == frame }
    }

    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        if reportOnly { attachScreenshot(app, "screen-\(screen)") }
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
