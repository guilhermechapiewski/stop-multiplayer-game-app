public enum Phase: Codable, Sendable, Equatable {
    case lobby
    case revealing(ticksRemaining: Int)
    case countdown(secondsRemaining: Int)
    case writing
    case collecting
    case scoring(categoryIndex: Int, completed: Bool)
    case roundResults
    case gameOver
}
