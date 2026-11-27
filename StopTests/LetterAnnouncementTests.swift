import Foundation
import StopCore
import Testing
@testable import Stop

@MainActor
struct LetterAnnouncementTests {
    @Test func announcesEachRoundOfEachGameOnce() {
        let game = UUID()
        let round = Round(number: 1, letter: "B", participants: [])
        #expect(LetterAnnouncement.announce(round, gameID: game))
        #expect(!LetterAnnouncement.announce(round, gameID: game))
        // A new game's first round can draw the same letter: it's announced again.
        #expect(LetterAnnouncement.announce(round, gameID: UUID()))
    }
}
