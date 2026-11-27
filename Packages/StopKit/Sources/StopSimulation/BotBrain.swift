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

    /// Chance that the bot fills every category in a round (otherwise it struggles).
    public var finishProbability: Double {
        switch self {
        case .relaxed: 0.35
        case .normal: 0.55
        case .fast: 0.75
        }
    }
}

/// What a bot writes in one round.
public struct BotRoundPlan: Sendable, Equatable {
    /// One non-blank answer per category.
    public var answers: [String]
    /// Categories the bot can't think of in time: it leaves them blank and gives up if it may, else guesses
    /// them last. Empty when the bot finishes the round.
    public var late: [Int]
    /// Categories answered with a guess rather than a known answer for the category (a bank word from another
    /// category, or a late guess): an honest bot scores these 0.
    public var guessed: Set<Int>
    public var finishes: Bool { late.isEmpty }
}

/// Decides a practice bot's answers, STOP timing and self-scores. Deterministic per seed.
public struct BotBrain: Sendable {
    /// When struggling, the probability that the bot blanks a category even when it knows an answer.
    static let blankProbability = 0.15

    private let bank: BotAnswerBank
    private let speed: BotSpeed
    private var rng: SplitMix64
    /// This bot's position among the game's bots; it picks a different slot of the shared shuffle.
    private let index: Int
    /// Shared by every bot of a game so they shuffle each candidate list the same way.
    private let sharedSeed: UInt64

    /// `index` and `sharedSeed` spread the answers of bots in one game: give each bot its position and the
    /// same `sharedSeed`. A lone bot can omit them (its own `seed` is used as the shared one).
    public init(language: GameLanguage, speed: BotSpeed, seed: UInt64, index: Int = 0, sharedSeed: UInt64? = nil) {
        self.bank = BotAnswerBank.load(language)
        self.speed = speed
        self.rng = SplitMix64(seed: seed)
        self.index = index
        self.sharedSeed = sharedSeed ?? seed
    }

    /// Decides the round: finish (weighted by speed) or struggle. A finisher answers every category, from the
    /// bank or, when the category has nothing for the letter (custom categories), with any bank word starting
    /// with it. A struggler blanks unknown categories and each known one with `blankProbability` (at least one).
    /// Bots of one game spread across each candidate list (see `pick`), so they collide only when it is short.
    /// Never answers one of `avoiding` (the players' names: "Ana" for Name when Ana is playing reads like a
    /// joke at her expense), compared ignoring case and accents.
    public mutating func plan(categories: [String], letter: String, round: Int = 0,
                              avoiding: [String] = []) -> BotRoundPlan {
        let avoided = Set(avoiding.map(BotAnswerBank.fold))
        let allowed = { (word: String) in !avoided.contains(BotAnswerBank.fold(word)) }
        let fallback = bank.anyCandidates(letter: letter).filter(allowed)
        let finishes = Double.random(in: 0..<1, using: &rng) < speed.finishProbability
        var answers: [String] = []
        var late: [Int] = []
        var guessed: Set<Int> = []
        for (position, category) in categories.enumerated() {
            let candidates = bank.candidates(category: category, letter: letter).filter(allowed)
            if !finishes, candidates.isEmpty || Double.random(in: 0..<1, using: &rng) < Self.blankProbability {
                late.append(position)
            }
            if candidates.isEmpty { guessed.insert(position) }
            let pool = candidates.isEmpty ? fallback : candidates
            answers.append(pick(from: pool, round: round, letter: letter, category: position) ?? letter)
        }
        if !finishes, late.isEmpty, !categories.isEmpty {
            late.append(Int.random(in: categories.indices, using: &rng))
        }
        return BotRoundPlan(answers: answers, late: late, guessed: guessed.union(late))
    }

    /// Shuffles `pool` with a seed shared by the game's bots for this round, letter and category; bot k takes
    /// element k mod count, so up to `pool.count` bots answer differently.
    private func pick(from pool: [String], round: Int, letter: String, category: Int) -> String? {
        guard pool.count > 1 else { return pool.first }
        var mix = SplitMix64(seed: sharedSeed)
        let parts = [UInt64(bitPattern: Int64(round)), UInt64(category)]
            + letter.unicodeScalars.map { UInt64($0.value) }
        for part in parts { mix = SplitMix64(seed: mix.next() ^ part) }
        let shuffled = pool.shuffled(using: &mix)
        return shuffled[index % shuffled.count]
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
