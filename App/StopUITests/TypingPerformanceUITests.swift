import XCTest

/// Typing in an answer field must stay fast: each keystroke re-renders only that field and never touches the
/// network or the shared game model. Xcode records `XCTClockMetric` baselines per device; the assertion below
/// is the hard floor: 30 characters in under 3 s on average on the simulator (typing there takes about 1 s, so
/// only a pathological re-render regression trips it).
final class TypingPerformanceUITests: XCTestCase {
    private static let text = "Abracadabra Bento Baleia Bolo!"
    private static let maxAverage: TimeInterval = 3.0

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testTypingLatency() {
        XCTAssertEqual(Self.text.count, 30)
        let app = launchApp(UITest.mockGame)
        let game = GameSteps(app: app, test: self)
        game.startFromLobby()
        game.waitForWriting()
        let field = app.textFields["answerField-0"]
        field.tap()
        waitFor(app.keyboards.firstMatch)

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var durations: [TimeInterval] = []
        measure(metrics: [XCTClockMetric()], options: options) {
            // Start each run from an empty field.
            let current = (field.value as? String) ?? ""
            if !current.isEmpty, current != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            let started = Date()
            startMeasuring()
            field.typeText(Self.text)
            stopMeasuring()
            durations.append(Date().timeIntervalSince(started))
            XCTAssertEqual(field.value as? String, Self.text)
        }

        let average = durations.reduce(0, +) / Double(max(durations.count, 1))
        XCTAssertLessThan(average, Self.maxAverage, "typing 30 characters took \(average) s on average")
    }
}
