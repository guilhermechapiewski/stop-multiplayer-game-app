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
}
