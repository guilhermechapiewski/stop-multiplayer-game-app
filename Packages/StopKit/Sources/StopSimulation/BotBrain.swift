import StopCore

/// How quickly a practice bot calls STOP.
public enum BotSpeed: String, CaseIterable, Sendable {
    case relaxed, normal, fast

    /// The window the bot's STOP delay is drawn from.
    public var stopWindow: ClosedRange<Duration> {
        switch self {
        case .relaxed: .seconds(60) ... .seconds(90)
        case .normal: .seconds(35) ... .seconds(60)
        case .fast: .seconds(20) ... .seconds(35)
        }
    }
}

/// Decides a practice bot's answers, STOP timing and self-scores. Deterministic per seed.
public struct BotBrain: Sendable {
    /// Probability that the bot leaves a category blank even when it knows an answer.
    static let blankProbability = 0.15

    private let bank: BotAnswerBank
    private let speed: BotSpeed
    private var rng: SplitMix64

    public init(language: GameLanguage, speed: BotSpeed, seed: UInt64) {
        self.bank = BotAnswerBank.load(language)
        self.speed = speed
        self.rng = SplitMix64(seed: seed)
    }

    /// One answer per category, in order; `""` for a skipped or unknown category.
    public mutating func answers(categories: [String], letter: String) -> [String] {
        categories.map { category in
            let candidates = bank.candidates(category: category, letter: letter)
            guard !candidates.isEmpty, Double.random(in: 0..<1, using: &rng) >= Self.blankProbability
            else { return "" }
            return candidates.randomElement(using: &rng) ?? ""
        }
    }

    /// A random delay (millisecond resolution) within the speed's stop window.
    public mutating func stopDelay() -> Duration {
        let window = speed.stopWindow
        let lower = Self.milliseconds(window.lowerBound)
        let upper = Self.milliseconds(window.upperBound)
        return .milliseconds(Int64.random(in: lower...upper, using: &rng))
    }

    /// Blank → 0; matches any other answer (trimmed, ignoring case and accents) → 5; else 10.
    public static func selfScore(mine: String, others: [String]) -> Int {
        guard !AnswerText.isBlank(mine) else { return 0 }
        let folded = BotAnswerBank.fold(mine)
        return others.contains { BotAnswerBank.fold($0) == folded } ? 5 : 10
    }

    private static func milliseconds(_ d: Duration) -> Int64 {
        let (seconds, attoseconds) = d.components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}

/// Seedable SplitMix64 generator so bots are reproducible.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
