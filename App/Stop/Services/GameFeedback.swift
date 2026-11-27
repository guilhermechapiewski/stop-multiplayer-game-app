/// Moments in a round that deserve a haptic or a sound. The round screens report them here; for now this
/// does nothing (haptics and synthesized sounds arrive in Task 18).
enum GameFeedbackEvent: Equatable {
    case letterRevealed
    case countdownTick(Int)
    case writingStarted
    case stopTapped
    case roundLocked
    case scorePicked
    case categoryCompleted
    case winner
}

@MainActor
enum GameFeedback {
    static func play(_ event: GameFeedbackEvent) {}
}
