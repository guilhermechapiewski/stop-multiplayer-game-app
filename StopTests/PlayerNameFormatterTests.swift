import Foundation
import StopCore
import Testing
@testable import Stop

struct PlayerNameFormatterTests {
    private func player(_ name: String, _ presence: Presence = .present) -> Player {
        Player(id: UUID(), name: name, presence: presence)
    }

    @Test func duplicateNamesGetSuffix() {
        let players = [player("Ana"), player("Gui"), player("Ana"), player("ana", .left)]
        let names = PlayerNameFormatter.displayNames(for: players)
        #expect(players.map { names[$0.id] } == ["Ana", "Gui", "Ana 2", "ana 3"])
    }

    @Test func uniqueNamesAreUnchanged() {
        let players = [player("Ana"), player("Bia")]
        let names = PlayerNameFormatter.displayNames(for: players)
        #expect(players.map { names[$0.id] } == ["Ana", "Bia"])
    }

    @Test func suffixSkipsNamesAlreadyTaken() {
        let players = [player("Ana"), player("Ana 2"), player("Ana")]
        let names = PlayerNameFormatter.displayNames(for: players)
        #expect(players.map { names[$0.id] } == ["Ana", "Ana 2", "Ana 3"])
    }
}
