import Testing
@testable import Stop

struct PlayerInitialTests {
    @Test(arguments: [
        ("Ana", false, "A"),
        ("bia", false, "B"),
        ("", false, "?"),
        ("Robo Ana", true, "A"),
        ("Robô Beto", true, "B"),
        ("Robo Cris 2", true, "C"),
        ("Robo", true, "R"),
    ])
    func initialFollowsTheNameAndBotsUseTheirOwnName(name: String, isBot: Bool, expected: String) {
        #expect(PlayerInitial.initial(for: name, isBot: isBot) == expected)
    }

    @Test(arguments: [
        // name, isBot, isPractice, isYou, expected
        ("Robo Ana", false, true, false, true),
        ("Robo Ana", true, false, false, true),
        ("Robo Gui", false, true, true, false),
        ("Robo Gui", false, false, false, false),
        ("Ana", false, true, false, false),
    ])
    func botInitialOnlyForOtherPlayersInPractice(name: String, isBot: Bool, isPractice: Bool, isYou: Bool,
                                                 expected: Bool) {
        #expect(PlayerInitial.showsBotInitial(name: name, isBot: isBot, isPractice: isPractice, isYou: isYou)
                == expected)
    }
}
