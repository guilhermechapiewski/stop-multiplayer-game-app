import Foundation
import StopCore
import Testing
@testable import Stop

@MainActor
struct GameMenuPracticeTests {
    @Test(arguments: [
        (nil, false),
        (.lobby, false),
        (.revealing(ticksRemaining: 2), true),
        (.countdown(secondsRemaining: 3), true),
        (.collecting, true),
        (.writing, true),
        (.scoring(categoryIndex: 0, completed: false), true),
        (.roundResults, true),
        (.gameOver, false),
    ] as [(Phase?, Bool)])
    func endingPracticeShowsStandingsOnlyOnceRoundsAreUnderWay(phase: Phase?, showsStandings: Bool) {
        #expect(GameMenu.endingPracticeShowsStandings(phase: phase) == showsStandings)
    }

    func session(phase: Phase) throws -> FakeRemoteSession {
        let session = FakeRemoteSession(playerID: UUID())
        var state = try GameEngine.newGame(
            gameID: UUID(), hostID: session.localPlayerID, hostName: "Gui",
            settings: GameSettings(categories: ["Animal"], stopsRequired: 1, allowGiveUp: true), language: .en)
        state.phase = phase
        session.state = state
        return session
    }

    @Test func endingPracticeMidGameEndsTheGame() throws {
        let session = try session(phase: .roundResults)
        var left = false
        GameMenu.endPractice(client: session) { left = true }
        #expect(session.sent == [.endGame])
        #expect(!left)
    }

    @Test(arguments: [Phase.lobby, .gameOver])
    func endingPracticeOutsideRoundsGoesHome(phase: Phase) throws {
        let session = try session(phase: phase)
        var left = false
        GameMenu.endPractice(client: session) { left = true }
        #expect(session.sent.isEmpty)
        #expect(left)
    }
}
