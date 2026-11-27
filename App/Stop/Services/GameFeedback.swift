/// Moments in a round that deserve a haptic or a sound. The round screens report them here.
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

/// The haptics `Haptics` can play, so the event → feedback mapping can be tested.
enum HapticCue: Equatable {
    case letterLanded, tick, stop, select, success
}

@MainActor
enum GameFeedback {
    /// What each moment plays. Tapping STOP only thumps: the sound comes with the stamp when the round locks.
    nonisolated static func cues(for event: GameFeedbackEvent) -> (haptic: HapticCue?, sound: Sound?) {
        switch event {
        case .letterRevealed: (.letterLanded, .reveal)
        case .countdownTick: (.tick, .tick)
        case .writingStarted: (.letterLanded, .go)
        case .stopTapped: (.stop, nil)
        case .roundLocked: (.stop, .stop)
        case .scorePicked: (.select, .pick)
        case .categoryCompleted: (.tick, .go)
        case .winner: (.success, .win)
        }
    }

    static func play(_ event: GameFeedbackEvent) {
        let cues = cues(for: event)
        switch cues.haptic {
        case .letterLanded: Haptics.letterLanded()
        case .tick: Haptics.tick()
        case .stop: Haptics.stop()
        case .select: Haptics.select()
        case .success: Haptics.success()
        case nil: break
        }
        if let sound = cues.sound { SoundEngine.shared.play(sound) }
    }
}
