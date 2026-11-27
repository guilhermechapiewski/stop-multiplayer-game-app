import Foundation
import StopCore
import Testing
@testable import Stop

struct AccessibilityLabelTests {
    private static let en = Locale(identifier: "en")
    private static let ptBR = Locale(identifier: "pt-BR")

    @Test(arguments: [(10, "10 points"), (5, "5 points"), (0, "0 points"), (1, "1 point")])
    func scoreButtonLabels(points: Int, expected: String) {
        #expect(AccessibilityText.score(points, locale: Self.en) == expected)
    }

    @Test(arguments: [(10, "10 pontos"), (5, "5 pontos"), (0, "0 pontos"), (1, "1 ponto")])
    func scoreButtonLabelsInPortuguese(points: Int, expected: String) {
        #expect(AccessibilityText.score(points, locale: Self.ptBR) == expected)
    }

    @Test func portugueseLetterAndChipLabels() {
        #expect(AccessibilityText.letter("B", locale: Self.ptBR) == "Letra B")
        #expect(AccessibilityText.playerDetails(presence: .away, isHost: true, isYou: true, isBot: false,
                                                locale: Self.ptBR) == "Quem criou o jogo, Você, Reconectando")
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
