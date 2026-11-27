import Foundation
import Observation
import StopCore
import StopSession

/// A computer player driving a real `ClientSession`. During writing it types its `BotBrain` answers one by
/// one (local draft only) and stops once it has filled what it can; in scoring it scores itself honestly.
/// It never touches the host or the lobby: the host's player runs those.
@MainActor public final class BotPlayer {
    public struct Behavior: Sendable {
        /// When the bot is done typing and stops; nil draws it from `speed` each round.
        public var stopAfter: Duration?
        /// Gives up (when the game allows it) this long into writing if it hasn't stopped yet.
        public var giveUpAfter: Duration?
        /// Thinking time before each self-score.
        public var scoreDelay: Duration
        public var speed: BotSpeed
        /// When done typing, waits until someone else has stopped before stopping.
        public var stopWhenOthersStopped: Bool

        public init(stopAfter: Duration?, giveUpAfter: Duration?, scoreDelay: Duration, speed: BotSpeed = .normal,
                    stopWhenOthersStopped: Bool = false) {
            self.stopAfter = stopAfter
            self.giveUpAfter = giveUpAfter
            self.scoreDelay = scoreDelay
            self.speed = speed
            self.stopWhenOthersStopped = stopWhenOthersStopped
        }

        public static let `default` = Behavior(stopAfter: .seconds(20), giveUpAfter: nil,
                                               scoreDelay: .milliseconds(800))

        /// Practice mode: stop timing drawn from `speed`.
        public static func practice(_ speed: BotSpeed) -> Behavior {
            Behavior(stopAfter: nil, giveUpAfter: nil, scoreDelay: .milliseconds(800), speed: speed)
        }
    }

    public let name: String
    public let client: ClientSession
    public let behavior: Behavior
    private let clock: any Clock<Duration>
    private let seed: UInt64
    private var brain: BotBrain?

    private var observer: Task<Void, Never>?
    private var writing: Task<Void, Never>?
    private var scoring: Task<Void, Never>?
    /// The round being typed, its answers so far, and whether typing finished / the bot stopped.
    private var writingRound: Int?
    /// What the bot has typed in the current (or last) round: local only, like a person's text fields.
    public private(set) var typed: [String] = []
    private var doneTyping = false
    private var hasStopped = false
    /// Categories of `writingRound` the bot only guessed; it scores them 0.
    private var guessed: Set<Int> = []
    private var scoringKey: (round: Int, category: Int)?
    /// The self-score sent and not yet seen in a snapshot; not re-sent until a reconnect or `scoreResendAfter`.
    private var scoreSent: (round: Int, category: Int)?
    private static let scoreResendAfter: Duration = .seconds(5)

    public init(name: String, client: ClientSession, behavior: Behavior = .default, clock: any Clock<Duration>,
                seed: UInt64 = .random(in: .min ... .max)) {
        self.name = name
        self.client = client
        self.behavior = behavior
        self.clock = clock
        self.seed = seed
    }

    private var me: PlayerID { client.localPlayerID }

    /// Starts reacting to the client's state until the game ends for it. Start the client separately.
    public func run() {
        guard observer == nil else { return }
        let client = client
        observer = Task { [weak self] in
            var wasConnected = false
            for await (state, status) in Observations({ (client.state, client.hostStatus) }) {
                guard let self else { return }
                if case .ended = status { return self.cancel() }
                if status == .connected, !wasConnected { self.reconnected() }
                wasConnected = status == .connected
                if let state { self.react(to: state) }
            }
        }
    }

    /// Stops all bot activity (the client keeps running).
    public func cancel() {
        for task in [observer, writing, scoring] { task?.cancel() }
        observer = nil
        writing = nil
        scoring = nil
    }

    // MARK: Reacting

    private func react(to state: GameState) {
        guard let round = state.currentRound, round.participants.contains(me) else { return }
        if round.number != writingRound, state.phase == .writing { beginWriting(state, round) }
        if round.stops.contains(where: { $0.playerID == me }) { hasStopped = true }
        switch state.phase {
        case .writing:
            if behavior.stopWhenOthersStopped, doneTyping, round.stops.contains(where: { $0.playerID != me }) {
                stop(allowGiveUp: state.settings.allowGiveUp)
            }
        case .scoring(let category, false):
            stopTyping()
            scheduleScore(round: round.number, category: category,
                          scored: round.scores[me]?[category] != nil)
        default:
            stopTyping()
        }
    }

    // MARK: Writing

    private func beginWriting(_ state: GameState, _ round: Round) {
        stopTyping()
        writingRound = round.number
        doneTyping = false
        hasStopped = false
        let categories = state.settings.categories
        typed = Array(repeating: "", count: categories.count)
        var brain = brain ?? BotBrain(language: state.language, speed: behavior.speed, seed: seed)
        let roundPlan = brain.plan(categories: categories, letter: round.letter)
        let stopAt = behavior.stopAfter ?? brain.stopDelay()
        self.brain = brain
        let planned = roundPlan.answers
        guessed = roundPlan.guessed
        let allowGiveUp = state.settings.allowGiveUp
        // A struggling bot leaves its late categories blank and gives up if it may; otherwise it guesses them
        // last and still STOPs.
        let known = planned.indices.filter { !roundPlan.late.contains($0) }
        let order = allowGiveUp ? known : known + roundPlan.late

        enum Step { case type(Int), done, giveUp }
        // Answers appear evenly spread before `stopAt`; a give-up due at the same moment comes first.
        var plan = order.enumerated().map { (at: stopAt / (order.count + 1) * ($0.offset + 1), step: Step.type($0.element)) }
        plan.append((stopAt, .done))
        if let giveUp = behavior.giveUpAfter { plan.insert((giveUp, .giveUp), at: 0) }
        plan = plan.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)

        let number = round.number
        writing = Task { [weak self, clock] in
            var elapsed = Duration.zero
            for item in plan {
                do { try await clock.sleep(for: item.at - elapsed) } catch { return }
                elapsed = item.at
                guard !Task.isCancelled, let self, self.writingRound == number, !self.hasStopped else { return }
                switch item.step {
                case .type(let index):
                    self.typed[index] = planned[index]
                    self.client.saveDraft(self.typed)
                case .done:
                    self.doneTyping = true
                    if !self.behavior.stopWhenOthersStopped || self.othersStopped {
                        self.stop(allowGiveUp: allowGiveUp)
                    }
                case .giveUp:
                    if allowGiveUp { self.send(.giveUp(answers: self.typed)) }
                }
            }
        }
    }

    private var othersStopped: Bool {
        client.state?.currentRound?.stops.contains { $0.playerID != me } ?? false
    }

    /// STOP when every answer is filled; otherwise give up if allowed, or keep waiting for the lock.
    private func stop(allowGiveUp: Bool) {
        guard !hasStopped else { return }
        if !typed.contains(where: AnswerText.isBlank) {
            send(.stop(answers: typed))
        } else if allowGiveUp {
            send(.giveUp(answers: typed))
        }
    }

    private func send(_ intent: Intent) {
        guard !hasStopped, client.state?.phase == .writing else { return }
        hasStopped = true
        stopTyping()
        client.send(intent)
    }

    private func stopTyping() {
        writing?.cancel()
        writing = nil
    }

    // MARK: Scoring

    /// A score in flight may have been lost with the old connection: allow sending it again.
    private func reconnected() {
        guard scoreSent != nil else { return }
        scoreSent = nil
        scoring?.cancel()
        scoring = nil
    }

    /// Scores the bot's own answer for `category` after `scoreDelay`, unless someone already did. Called on
    /// every snapshot; once sent, it is sent again only if the score is still missing after a reconnect or
    /// `scoreResendAfter`.
    private func scheduleScore(round: Int, category: Int, scored: Bool) {
        let same = scoringKey?.round == round && scoringKey?.category == category
        guard !scored, !same || scoring == nil else { return }
        if let sent = scoreSent, sent.round == round, sent.category == category { return }
        scoringKey = (round, category)
        scoring?.cancel()
        scoring = Task { [weak self, clock, behavior] in
            do { try await clock.sleep(for: behavior.scoreDelay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.scoring = nil
            guard let state = self.client.state, let current = state.currentRound,
                  current.number == round, state.phase == .scoring(categoryIndex: category, completed: false),
                  current.scores[self.me]?[category] == nil, let mine = current.answers[self.me]?[category]
            else { return }
            let others = current.answers.filter { $0.key != self.me }.compactMap { $0.value[safe: category] }
            let honest = round == self.writingRound && self.guessed.contains(category)
            let points = honest ? 0 : BotBrain.selfScore(mine: mine, others: others)
            self.client.send(.setScore(round: round, category: category, points: points, player: self.me))
            self.scoreSent = (round, category)
            self.scoring = Task { [weak self, clock] in
                do { try await clock.sleep(for: Self.scoreResendAfter) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.scoreSent = nil
                self.scoring = nil
                if let state = self.client.state { self.react(to: state) }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
