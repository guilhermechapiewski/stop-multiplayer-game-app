import Testing
@testable import Stop

struct SoundSpecTests {
    @Test(arguments: Sound.allCases)
    func soundSpecsAreShortAndAudible(sound: Sound) {
        let spec = sound.spec
        #expect(!spec.notes.isEmpty)
        #expect(spec.duration < 0.6)
        #expect(spec.peakAmplitude >= 0.1 && spec.peakAmplitude <= 0.9)
        #expect(spec.notes.allSatisfy { $0.frequency >= 100 && $0.frequency <= 4_000 })
    }

    @Test(arguments: Sound.allCases)
    func renderedSamplesStayUnderThePeakAndDontClick(sound: Sound) {
        let spec = sound.spec
        let samples = spec.render(sampleRate: 44_100)
        #expect(abs(samples.count - Int(spec.duration * 44_100)) <= spec.notes.count)
        let peak = samples.map(abs).max() ?? 0
        #expect(peak <= Float(spec.peakAmplitude) + 0.001)
        #expect(peak > 0.05)
        // Starts and ends (near) silent, so there's no click.
        #expect(abs(samples.first ?? 1) < 0.01)
        #expect(abs(samples.last ?? 1) < 0.02)
    }

    @Test func everyMomentPlaysAHapticAndTheStampPlaysTheStopSound() {
        let events: [GameFeedbackEvent] = [.letterRevealed, .countdownTick(3), .writingStarted, .stopTapped,
                                           .roundLocked, .scorePicked, .categoryCompleted, .winner]
        #expect(events.allSatisfy { GameFeedback.cues(for: $0).haptic != nil })
        #expect(GameFeedback.cues(for: .roundLocked).sound == .stop)
        #expect(GameFeedback.cues(for: .stopTapped).sound == nil)
        #expect(GameFeedback.cues(for: .winner) == (.success, .win))
    }
}
