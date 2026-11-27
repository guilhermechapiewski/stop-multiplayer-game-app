import AVFoundation
import Foundation

/// The game's sound effects. Each is synthesized from a `ToneSpec` at runtime: the app ships no audio files.
enum Sound: CaseIterable, Sendable {
    /// The round's letter lands.
    case reveal
    /// A countdown second (3, 2, 1).
    case tick
    /// Writing starts; a scoring category is complete.
    case go
    /// A score button is tapped.
    case pick
    /// The round locks under the STOP! stamp.
    case stop
    /// The local player won the game.
    case win

    var spec: ToneSpec {
        switch self {
        case .reveal: ToneSpec([.init(784, 0.07, .bell, 0.32), .init(1175, 0.24, .bell, 0.34)])
        case .tick: ToneSpec([.init(1046, 0.06, .triangle, 0.28)])
        case .go: ToneSpec([.init(659, 0.07, .triangle, 0.3), .init(988, 0.16, .triangle, 0.32)])
        case .pick: ToneSpec([.init(880, 0.045, .sine, 0.24)])
        case .stop: ToneSpec([.init(330, 0.05, .square, 0.16), .init(196, 0.24, .triangle, 0.45)])
        case .win: ToneSpec([.init(523, 0.09, .triangle, 0.3), .init(659, 0.09, .triangle, 0.3),
                             .init(784, 0.09, .triangle, 0.3), .init(1047, 0.26, .bell, 0.34)])
        }
    }
}

/// A short sequence of enveloped notes: quick linear attack, then a squared decay to silence, so every note
/// starts and ends at zero (no clicks).
struct ToneSpec: Equatable, Sendable {
    enum Waveform: Sendable { case sine, triangle, square, bell }

    struct Note: Equatable, Sendable {
        /// Hz.
        let frequency: Double
        /// Seconds.
        let duration: Double
        let waveform: Waveform
        /// Peak amplitude, 0…1.
        let gain: Double

        init(_ frequency: Double, _ duration: Double, _ waveform: Waveform, _ gain: Double) {
            self.frequency = frequency
            self.duration = duration
            self.waveform = waveform
            self.gain = gain
        }
    }

    let notes: [Note]
    /// Seconds to reach each note's peak.
    var attack = 0.004

    init(_ notes: [Note]) { self.notes = notes }

    var duration: Double { notes.reduce(0) { $0 + $1.duration } }
    var peakAmplitude: Double { notes.map(\.gain).max() ?? 0 }

    /// Mono samples at `sampleRate`.
    func render(sampleRate: Double) -> [Float] {
        var samples: [Float] = []
        samples.reserveCapacity(Int(duration * sampleRate) + notes.count)
        for note in notes {
            let count = Int(note.duration * sampleRate)
            let attackCount = max(1, min(count - 1, Int(attack * sampleRate)))
            for index in 0..<count {
                let time = Double(index) / sampleRate
                let phase = (time * note.frequency).truncatingRemainder(dividingBy: 1)
                let envelope = index < attackCount
                    ? Double(index) / Double(attackCount)
                    : pow(1 - Double(index - attackCount) / Double(max(1, count - 1 - attackCount)), 2)
                samples.append(Float(Self.wave(note.waveform, phase: phase) * envelope * note.gain))
            }
        }
        return samples
    }

    /// One cycle of `waveform` at `phase` (0..<1), peaking at ±1.
    private static func wave(_ waveform: Waveform, phase: Double) -> Double {
        switch waveform {
        case .sine: sin(2 * .pi * phase)
        case .triangle: 4 * abs(phase - 0.5) - 1
        case .square: phase < 0.5 ? 1 : -1
        // A sine with a soft octave overtone: a little brighter, like a small bell.
        case .bell: (sin(2 * .pi * phase) + 0.3 * sin(4 * .pi * phase)) / 1.3
        }
    }
}

/// The audio graph `SoundEngine` drives: a seam so tests can check the engine's bookkeeping (build once,
/// start without side effects) without real audio.
@MainActor
protocol SoundGraph: AnyObject {
    /// One-time setup: session category, nodes and a buffer per sound. False if it couldn't be built.
    func build(samples: [Sound: [Float]], sampleRate: Double) -> Bool
    var isRunning: Bool { get }
    /// Starts the engine. Leaves the graph as it was if it throws.
    func start() throws
    func pause()
    func schedule(_ sound: Sound)
    /// Called when an interruption ends or the audio configuration changes, which stop the engine.
    var onNeedsRestart: (() -> Void)? { get set }
}

/// Plays `Sound`s. Off unless `enabled` (the Settings toggle; always off under `-uiTesting`). The graph is
/// built once, on the first warm-up or sound; the engine runs only while sounds play, pausing after a few
/// idle seconds, when disabled and in the background.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine(graph: AVSoundGraph())

    /// Mirrors the player's Sounds setting (set by `RootView`).
    var enabled = false {
        didSet { if !enabled { pause() } }
    }

    static let sampleRate = 44_100.0
    private static let idleDelay: Duration = .seconds(8)

    private let graph: any SoundGraph
    private(set) var isGraphBuilt = false
    private var idleTask: Task<Void, Never>?

    init(graph: any SoundGraph) {
        self.graph = graph
        graph.onNeedsRestart = { [weak self] in self?.restartIfActive() }
    }

    func play(_ sound: Sound) {
        guard enabled, buildGraphIfNeeded(), startIfNeeded() else { return }
        graph.schedule(sound)
        scheduleIdlePause()
    }

    /// Builds and starts the engine ahead of the first sound (on entering a game), so that one isn't late.
    func warmUp() {
        guard enabled, buildGraphIfNeeded(), startIfNeeded() else { return }
        scheduleIdlePause()
    }

    /// Stops the engine's IO (backgrounded, disabled or idle). The next sound starts it again.
    func pause() {
        idleTask?.cancel()
        idleTask = nil
        if isGraphBuilt, graph.isRunning { graph.pause() }
    }

    private func buildGraphIfNeeded() -> Bool {
        guard !isGraphBuilt else { return true }
        var samples: [Sound: [Float]] = [:]
        for sound in Sound.allCases { samples[sound] = sound.spec.render(sampleRate: Self.sampleRate) }
        isGraphBuilt = graph.build(samples: samples, sampleRate: Self.sampleRate)
        return isGraphBuilt
    }

    private func startIfNeeded() -> Bool {
        if graph.isRunning { return true }
        do { try graph.start() } catch { return false }
        return true
    }

    /// After an interruption or a configuration change, resume only if sounds were playing recently.
    private func restartIfActive() {
        guard enabled, isGraphBuilt, idleTask != nil else { return }
        _ = startIfNeeded()
    }

    private func scheduleIdlePause() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.idleDelay) } catch { return }
            self?.pause()
        }
    }
}

/// The real graph: `AVAudioEngine` with a few player nodes into the main mixer, on the `.ambient` session so
/// it mixes with other audio and the silent switch mutes it.
@MainActor
final class AVSoundGraph: SoundGraph {
    var onNeedsRestart: (() -> Void)?

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var observers: [any NSObjectProtocol] = []

    var isRunning: Bool { engine.isRunning }

    func build(samples: [Sound: [Float]], sampleRate: Double) -> Bool {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return false }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        // ~10 ms instead of the default ~20 ms keeps sounds in step with the screen without extra wakeups.
        try? session.setPreferredIOBufferDuration(0.01)
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            try? engine.connectNode(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.8
        for (sound, data) in samples { buffers[sound] = Self.buffer(data, format: format) }
        observeInterruptions()
        return true
    }

    func start() throws { try engine.start() }

    func pause() { engine.pause() }

    func schedule(_ sound: Sound) {
        guard let buffer = buffers[sound], !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        // `.interrupts` replaces whatever this node was playing without a blocking `stop()`.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { try? player.playAudio() }
    }

    /// The end of an interruption (a call, Siri) or a route/format change leaves the engine stopped.
    private func observeInterruptions() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification,
                                            object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onNeedsRestart?() }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                            queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onNeedsRestart?() }
        })
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        return buffer
    }
}
