import Foundation
import Observation
import StopCore
import StopSession
import Testing
@testable import Stop

@MainActor
struct WritingModelTests {
    let client = RecordingGameClient()

    @Test func allFilledIgnoresWhitespace() {
        let model = WritingModel(categoryCount: 2, client: client, initial: nil)
        #expect(!model.allFilled)
        #expect(!model.availability.allFilled)

        model.update(index: 0, text: "Bear")
        model.update(index: 1, text: "   ")
        #expect(!model.allFilled)
        #expect(!model.availability.allFilled)

        model.update(index: 1, text: " Brazil ")
        #expect(model.allFilled)
        #expect(model.availability.allFilled)

        model.update(index: 0, text: "\n")
        #expect(!model.allFilled)
        #expect(!model.availability.allFilled)
    }

    /// Keystrokes that don't flip "all filled" must not invalidate the STOP button.
    @Test func keystrokeWithoutFlipDoesNotInvalidateAvailability() {
        let model = WritingModel(categoryCount: 2, client: client, initial: nil)
        nonisolated(unsafe) var changes = 0
        func track() {
            withObservationTracking { _ = model.availability.allFilled } onChange: { changes += 1 }
        }

        track()
        model.update(index: 0, text: "B")
        model.update(index: 0, text: "Be")
        model.update(index: 1, text: "B")
        #expect(changes == 1) // only the flip to filled

        track()
        model.update(index: 1, text: "Br")
        model.update(index: 0, text: "Bear")
        #expect(changes == 1)

        model.update(index: 1, text: " ")
        #expect(changes == 2) // the flip back
    }

    @Test func updateSavesDraft() {
        let model = WritingModel(categoryCount: 3, client: client, initial: nil)

        model.update(index: 1, text: "B")
        model.update(index: 1, text: "Br")

        #expect(client.savedDrafts == [["", "B", ""], ["", "Br", ""]])
        #expect(model.answers == ["", "Br", ""])
        #expect(client.sent.isEmpty)
    }

    @Test func stopSendsAnswers() {
        let model = WritingModel(categoryCount: 2, client: client, initial: nil)
        model.update(index: 0, text: "Bear")
        model.update(index: 1, text: "Brazil")

        model.stop()

        #expect(client.sent == [.stop(answers: ["Bear", "Brazil"])])
    }

    @Test func giveUpSendsBlanksAllowed() {
        let model = WritingModel(categoryCount: 3, client: client, initial: nil)
        model.update(index: 0, text: "Bear")

        model.giveUp()

        #expect(client.sent == [.giveUp(answers: ["Bear", "", ""])])
    }

    @Test func initialDraftSeedsAnswers() {
        let model = WritingModel(categoryCount: 3, client: client, initial: ["Bear", "Brazil", "Banana"])
        #expect(model.answers == ["Bear", "Brazil", "Banana"])
        #expect(model.allFilled)
        #expect(model.availability.allFilled)
        #expect(client.savedDrafts.isEmpty)

        // A draft of the wrong length is padded or trimmed to the categories.
        let short = WritingModel(categoryCount: 3, client: client, initial: ["Bear"])
        #expect(short.answers == ["Bear", "", ""])
        let long = WritingModel(categoryCount: 1, client: client, initial: ["Bear", "Brazil"])
        #expect(long.answers == ["Bear"])
    }
}

/// A `GameClient` that records what it was asked to do.
@MainActor @Observable
final class RecordingGameClient: GameClient {
    var localPlayerID = UUID()
    var isHost = false
    var state: GameState?
    var hostStatus: HostStatus = .connected
    let presenceChanges = AsyncStream<PresenceChange> { $0.finish() }
    var lastError: GameError?
    var frozenAnswers: [String]?

    private(set) var sent: [Intent] = []
    private(set) var savedDrafts: [[String]] = []
    var storedDraft: [String]?

    func send(_ intent: Intent) { sent.append(intent) }
    func saveDraft(_ answers: [String]) { savedDrafts.append(answers) }
    func draft() async -> [String]? { storedDraft }
    func leave() {}
}
