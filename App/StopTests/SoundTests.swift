import Foundation
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

/// Records what `SoundEngine` asks of its graph; `start()` fails while `failStart` is set.
@MainActor
private final class FakeSoundGraph: SoundGraph {
    var onNeedsRestart: (() -> Void)?
    var builds = 0
    var starts = 0
    var pauses = 0
    var scheduled: [Sound] = []
    var failStart = false
    private(set) var isRunning = false

    func build(samples: [Sound: [Float]], sampleRate: Double) -> Bool {
        builds += 1
        return samples.count == Sound.allCases.count
    }

    func start() throws {
        starts += 1
        if failStart { throw CocoaError(.featureUnsupported) }
        isRunning = true
    }

    func pause() { pauses += 1; isRunning = false }
    func schedule(_ sound: Sound) { scheduled.append(sound) }
    func stopBehindTheEnginesBack() { isRunning = false }
}

@MainActor
struct SoundEngineTests {
    @Test func failedStartsDontRebuildTheGraph() {
        let graph = FakeSoundGraph()
        let engine = SoundEngine(graph: graph)
        engine.enabled = true
        graph.failStart = true
        engine.play(.tick)
        engine.play(.tick)
        engine.play(.stop)
        #expect(graph.builds == 1)
        #expect(graph.starts == 3)
        #expect(graph.scheduled.isEmpty)

        graph.failStart = false
        engine.play(.win)
        #expect(graph.builds == 1)
        #expect(graph.scheduled == [.win])
    }

    @Test func disabledEngineNeverTouchesAudio() {
        let graph = FakeSoundGraph()
        let engine = SoundEngine(graph: graph)
        engine.play(.tick)
        engine.warmUp()
        #expect(graph.builds == 0)
        #expect(graph.starts == 0)
    }

    @Test func disablingPausesAndARestartRequestResumesOnlyWhileActive() {
        let graph = FakeSoundGraph()
        let engine = SoundEngine(graph: graph)
        engine.enabled = true
        engine.warmUp()
        #expect(graph.isRunning)

        // An interruption stopped the engine; it resumes because sounds were active.
        graph.stopBehindTheEnginesBack()
        graph.onNeedsRestart?()
        #expect(graph.isRunning)

        engine.enabled = false
        #expect(!graph.isRunning)
        #expect(graph.pauses == 1)
        graph.onNeedsRestart?()
        #expect(!graph.isRunning)
    }
}
