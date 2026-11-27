public enum Intent: Codable, Sendable, Equatable {
    case join(name: String), leave, removePlayer(PlayerID)
    case updateSettings(GameSettings)                                // lobby only
    case updateRoundSettings(stopsRequired: Int, allowGiveUp: Bool, silentScoring: Bool)  // lobby or roundResults
    case startGame, nextRound, endGame, forceEndRound, continueToScoring
    case stop(answers: [String]), giveUp(answers: [String])
    case submitAnswers(round: Int, answers: [String])
    case setScore(round: Int, category: Int, points: Int, player: PlayerID)
    case nextCategory(round: Int, category: Int)                     // host, completed scoring category
    case previousCategory(round: Int, category: Int)                 // host, scoring category > 0 or results
    case rerollLetter(round: Int, letter: String)                    // host, letter reveal or countdown
}
