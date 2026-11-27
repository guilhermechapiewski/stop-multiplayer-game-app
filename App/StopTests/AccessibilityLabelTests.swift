import StopCore
import Testing
@testable import Stop

struct AccessibilityLabelTests {
    @Test(arguments: [(10, "10 points"), (5, "5 points"), (0, "0 points")])
    func scoreButtonLabels(points: Int, expected: String) {
        #expect(AccessibilityText.score(points) == expected)
    }

    @Test func presenceChipLabels() {
        #expect(AccessibilityText.playerDetails(presence: .present, isHost: false, isYou: false, isBot: false) == "")
        #expect(AccessibilityText.playerDetails(presence: .present, isHost: true, isYou: true, isBot: false)
                == "Host, You")
        #expect(AccessibilityText.playerDetails(presence: .away, isHost: false, isYou: false, isBot: false)
                == "Reconnecting")
        #expect(AccessibilityText.playerDetails(presence: .away, isHost: false, isYou: false, isBot: true)
                == "Bot, Reconnecting")
    }

    @Test func letterAnnouncement() {
        #expect(AccessibilityText.letter("B") == "Letter B")
    }
}

struct RoundResultsTitleTests {
    @Test func endButtonSaysPracticeInPracticeGames() {
        #expect(String(localized: RoundResultsView.endTitle(isPractice: true)) == "End practice")
        #expect(String(localized: RoundResultsView.endTitle(isPractice: false)) == "End game")
    }
}
