import Foundation
import StopCore
import StopNetworking
import StopSimulation
import StopTestSupport
import Testing
@testable import StopSession

private let categories = ["Name", "Animal", "Fruit"]

/// Polls `condition` (a millisecond between checks) and records an issue if it never holds.
@MainActor
private func waitUntil(_ what: String, _ condition: () async -> Bool) async {
    for _ in 0..<3000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("timed out waiting for \(what)")
}

/// A host played by the test plus bot clients, all on one in-memory network and test clock.
@MainActor
private final class Scenario {
    let net = InMemoryNetwork()
    let clock = TestClock()
    let hostStore = InMemoryGameStore()
    var host: HostSession
    private(set) var clients: [ClientSession] = []
    private(set) var bots: [BotPlayer] = []
    /// Rounds the host plays before ending the game.
    let rounds: Int
    /// The host types, scores itself and moves on from round results on its own.
    var hostAutoPlay = true
    /// With auto-play, the host also calls STOP with its typed answers as soon as writing starts.
    var hostStops = false
    /// Real time given to in-flight messages after each clock step (only needed with network latency).
    var realTimePerStep: Duration?
    private var hostDraftedRound = 0

    init(bots behaviors: [BotPlayer.Behavior], stopsRequired: Int = 1, allowGiveUp: Bool = true,
         rounds: Int = 1) throws {
        self.rounds = rounds
        let state = try GameEngine.newGame(
            gameID: UUID(), hostID: UUID(), hostName: "Gui",
            settings: GameSettings(categories: categories, stopsRequired: stopsRequired, allowGiveUp: allowGiveUp),
            language: .en)
        host = HostSession(state: state, factory: net, store: hostStore, clock: clock, rng: SeededRNG(seed: 7))
        host.start()
        for (index, behavior) in behaviors.enumerated() {
            let profile = Profile(playerID: UUID(), name: "Bot \(index + 1)", soundsEnabled: false)
            let client = ClientSession(profile: profile, target: .rejoin(gameID: state.gameID), factory: net,
                                       store: InMemoryGameStore(), clock: clock)
            let bot = BotPlayer(name: profile.name, client: client, behavior: behavior, clock: clock,
                                seed: UInt64(index + 1))
            clients.append(client)
            bots.append(bot)
        }
    }

    var hostID: PlayerID { host.state.hostID }
    func id(_ bot: Int) -> PlayerID { clients[bot].localPlayerID }
    func presence(_ bot: Int) -> Presence? { host.state.player(id(bot))?.presence }

    /// Connects every bot, waits for them in the lobby and starts the game.
    func start() async {
        for (bot, client) in zip(bots, clients) {
            bot.run()
            client.start()
        }
        await waitUntil("bots in the lobby") {
            clients.allSatisfy { host.state.player($0.localPlayerID)?.presence == .present && $0.state != nil }
        }
        host.localClient.send(.startGame)
        #expect(host.state.phase == .revealing(ticksRemaining: 2))
    }

    /// Moves the clock 250 ms, lets messages flow, and plays the host's part.
    func step() async {
        await clock.advance(by: .milliseconds(250))
        if let realTimePerStep {
            try? await Task.sleep(for: realTimePerStep)
        } else {
            for _ in 0..<5 { await Task.yield() }
            try? await Task.sleep(for: .milliseconds(1))
        }
        if hostAutoPlay { playHost() }
    }

    /// Steps until `done` holds, at most `seconds` of game time; records an issue if it never does.
    func run(_ what: String, seconds: Int = 120, until done: () -> Bool) async {
        for _ in 0..<(seconds * 4) {
            if done() { return }
            await step()
        }
        if !done() { Issue.record("never reached: \(what) (host phase \(host.state.phase))") }
    }

    func runToGameOver(seconds: Int = 240) async {
        await run("game over", seconds: seconds) { host.state.phase == .gameOver }
        await waitUntil("clients saw the game end") {
            clients.allSatisfy { $0.hostStatus == .ended(.gameOver) || $0.hostStatus == .ended(.leftGame) }
        }
    }

    /// Every client that stayed to the end has the host's totals and rounds.
    func expectConsistentEverywhere() {
        let totals = host.state.totals
        for client in clients where client.hostStatus == .ended(.gameOver) {
            #expect(client.state?.totals == totals, "\(client.profile.name)")
            #expect(client.state?.rounds == host.state.rounds, "\(client.profile.name)")
            #expect(client.state?.phase == .gameOver)
        }
    }

    /// The host (a human here) types placeholder answers, scores itself 10 and plays `rounds` rounds.
    private func playHost() {
        let state = host.state
        guard let round = state.currentRound else { return }
        switch state.phase {
        case .writing where hostDraftedRound != round.number:
            hostDraftedRound = round.number
            let answers = state.settings.categories.map { round.letter + $0.prefix(3) }
            host.localClient.saveDraft(answers)
            if hostStops { host.localClient.send(.stop(answers: answers)) }
        case .scoring(let category, false) where round.participants.contains(hostID):
            guard round.scores[hostID]?[category] == nil else { return }
            host.localClient.send(.setScore(round: round.number, category: category, points: 10, player: hostID))
        case .roundResults:
            host.localClient.send(state.rounds.count < rounds ? .nextRound : .endGame)
        default:
            break
        }
    }
}

private func bot(stopAfter: Duration? = .seconds(2), giveUpAfter: Duration? = nil,
                 scoreDelay: Duration = .milliseconds(800), stopWhenOthersStopped: Bool = false) -> BotPlayer.Behavior {
    BotPlayer.Behavior(stopAfter: stopAfter, giveUpAfter: giveUpAfter, scoreDelay: scoreDelay, speed: .fast,
                       stopWhenOthersStopped: stopWhenOthersStopped)
}

/// Effectively never stops on its own.
private let slowBot = bot(stopAfter: .seconds(1000))

@MainActor
@Suite struct ResilienceScenarioTests {
    @Test func fullGameThreeRoundsReachesGameOverWithConsistentStateEverywhere() async throws {
        let s = try Scenario(bots: [.default, .default, .default], stopsRequired: 2, rounds: 3)
        await s.start()
        await s.runToGameOver(seconds: 240)
        #expect(s.host.state.rounds.count == 3)
        for round in s.host.state.rounds {
            #expect(round.stops.count >= 2)
            #expect(round.scores.values.allSatisfy { $0.allSatisfy { $0 != nil } })
        }
        // Bots typed real answers and scored themselves.
        let botPoints = (0..<3).map { s.host.state.totals[s.id($0)] ?? 0 }
        #expect(botPoints.contains { $0 > 0 })
        s.expectConsistentEverywhere()
    }

    @Test func playerDropsDuringWritingAndReturns() async throws {
        // Bot 1 is the only one who stops; it drops before its STOP and returns 2 s later.
        let s = try Scenario(bots: [bot(stopAfter: .seconds(3)), slowBot, slowBot])
        await s.start()
        await s.run("writing") { s.host.state.phase == .writing }
        await s.step()
        s.clients[0].stop()
        await s.run("bot 1 away") { s.presence(0) == .away }
        // The bot stops while disconnected: the STOP waits in its queue and the round keeps going.
        await s.run("bot 1 stopped locally", seconds: 5) { s.clients[0].frozenAnswers != nil }
        #expect(s.host.state.phase == .writing)
        #expect(s.clients[0].pendingIntentCount >= 1)
        s.clients[0].start()
        await s.run("bot 1 back") { s.presence(0) == .present }
        await s.run("round locked by bot 1's stop") { s.host.state.phase != .writing }
        #expect(s.host.state.rounds[0].stops.map(\.playerID) == [s.id(0)])
        // The others' typed drafts were submitted at the lock.
        #expect(s.host.state.rounds[0].answers.count == 4)
        await s.runToGameOver()
        s.expectConsistentEverywhere()
    }

    @Test func playerDropsDuringScoringHostScoresForThem() async throws {
        let s = try Scenario(bots: [bot(), bot(), bot()], stopsRequired: 1, rounds: 2)
        await s.start()
        await s.run("scoring") {
            if case .scoring = s.host.state.phase { true } else { false }
        }
        s.clients[0].stop()
        await waitUntil("bot 1 away") { s.presence(0) == .away }
        // The host scores the away bot's open categories itself.
        var scoredForBot = 0
        await s.run("round results") {
            let state = s.host.state
            if case .scoring(let category, false) = state.phase, let round = state.currentRound,
               round.scores[s.id(0)]?[category] == nil {
                s.host.localClient.send(.setScore(round: round.number, category: category, points: 5,
                                                  player: s.id(0)))
                if s.host.localClient.lastError == nil { scoredForBot += 1 }
            }
            return state.rounds.count == 2
        }
        #expect(scoredForBot > 0)
        let botScores = s.host.state.rounds[0].scores[s.id(0)] ?? []
        #expect(botScores.allSatisfy { $0 == 0 || $0 == 5 })
        // Back in round 2: the bot's late round-1 self-scores are rejected and don't change the host's picks.
        s.clients[0].start()
        await s.runToGameOver()
        #expect(s.host.state.rounds[0].scores[s.id(0)] == botScores)
        #expect(s.host.state.rounds[1].scores[s.id(0)]?.allSatisfy { $0 != nil } == true)
        s.expectConsistentEverywhere()
    }

    @Test func hostSuspendsDuringCountdownEveryonePausesThenResumes() async throws {
        let s = try Scenario(bots: [bot(), bot(), bot()])
        await s.start()
        await s.run("countdown") { s.host.state.phase == .countdown(secondsRemaining: 3) }
        s.host.suspend()
        await waitUntil("clients see the host away") { s.clients.allSatisfy { $0.hostStatus == .away } }
        let paused = s.host.state
        // 4 s: less than the 6 s of silence after which clients recycle the connection.
        for _ in 0..<(4 * 4) { await s.step() }
        #expect(s.host.state.phase == paused.phase)
        #expect(s.host.state.version == paused.version)
        #expect(s.clients.allSatisfy { $0.state?.phase == paused.phase && $0.hostStatus == .away })
        s.host.resume()
        await s.run("everyone connected again") { s.clients.allSatisfy { $0.hostStatus == .connected } }
        #expect(s.host.state.players.allSatisfy { $0.presence == .present })
        await s.run("writing") { s.host.state.phase == .writing }
        await s.runToGameOver()
        s.expectConsistentEverywhere()
    }

    @Test func hostAppKilledAndRestoredMidRound() async throws {
        let s = try Scenario(bots: [bot(stopAfter: .seconds(4)), slowBot, slowBot], rounds: 2)
        await s.start()
        await s.run("writing") { s.host.state.phase == .writing }
        await s.step()
        // The host app dies: no goodbye, its listener and every connection vanish.
        let dead = s.host
        dead.listener?.stop()
        s.net.dropAllConnections()
        dead.suspend()
        await waitUntil("clients see the host away") { s.clients.allSatisfy { $0.hostStatus == .away } }
        var saved: GameState?
        await waitUntil("game persisted") {
            saved = await s.hostStore.loadHostGame()
            return saved?.phase == .writing
        }
        let persisted = try #require(saved)
        // Bots keep typing (and bot 1 stops) while the host is gone.
        for _ in 0..<(3 * 4) { await s.step() }
        // Relaunch: restore the persisted game in a new session on a new listener.
        let restored = HostSession(state: persisted, factory: s.net, store: s.hostStore, clock: s.clock,
                                   rng: SeededRNG(seed: 11))
        s.host = restored
        restored.start()
        #expect(restored.state.gameID == persisted.gameID)
        await s.run("clients rejoined") {
            (0..<3).allSatisfy { s.presence($0) == .present } && s.clients.allSatisfy { $0.hostStatus == .connected }
        }
        await s.run("round locked by bot 1's queued stop") { restored.state.phase != .writing }
        #expect(restored.state.rounds[0].stops.map(\.playerID) == [s.id(0)])
        await s.runToGameOver()
        #expect(restored.state.rounds.count == 2)
        s.expectConsistentEverywhere()
    }

    @Test func everyoneGivesUpTogether() async throws {
        let giveUp = bot(stopAfter: .seconds(1000), giveUpAfter: .seconds(2))
        let s = try Scenario(bots: [giveUp, giveUp, giveUp], stopsRequired: 4, allowGiveUp: true)
        await s.start()
        await s.run("writing") { s.host.state.phase == .writing }
        s.host.localClient.send(.giveUp(answers: ["", "", ""]))
        #expect(s.host.localClient.lastError == nil)
        await s.run("round locked") { s.host.state.phase != .writing }
        let round = s.host.state.rounds[0]
        #expect(round.stops.count == 4)
        #expect(round.stops.allSatisfy { $0.kind == .giveUp })
        await s.runToGameOver()
        s.expectConsistentEverywhere()
    }

    @Test func playerLeavesForGoodAndStaysInStandings() async throws {
        // Everyone must stop; bot 3 leaves early in round 2, which lowers the cap to the three still playing.
        let s = try Scenario(bots: [bot(), bot(), bot()], stopsRequired: 4, rounds: 2)
        s.hostStops = true
        await s.start()
        await s.run("round 1 results") { s.host.state.phase == .roundResults || s.host.state.rounds.count == 2 }
        let leaver = s.id(2)
        let roundOnePoints = Standings.roundPoints(s.host.state.rounds[0])[leaver] ?? 0
        await s.run("round 2 writing") { s.host.state.rounds.count == 2 && s.host.state.phase == .writing }
        s.clients[2].leave()
        await s.run("bot 3 left") { s.clients[2].hostStatus == .ended(.leftGame) }
        #expect(s.presence(2) == .left)
        await s.runToGameOver()
        let state = s.host.state
        #expect(state.rounds.count == 2)
        #expect(state.rounds[0].stops.count == 4)
        #expect(state.rounds[1].stops.count == 3)
        #expect(!state.rounds[1].stops.contains { $0.playerID == leaver })
        #expect(state.rounds[1].scores[leaver]?.allSatisfy { $0 == 0 } == true)
        #expect(state.totals[leaver] ?? 0 == roundOnePoints)
        #expect(state.player(leaver)?.presence == .left)
        let standings = Standings.rank(state.totals, players: state.players)
        #expect(standings.contains { $0.playerID == leaver && $0.points == roundOnePoints })
        s.expectConsistentEverywhere()
    }

    @Test func botWaitingForOthersStopsOnlyAfterSomeoneElseDoes() async throws {
        let s = try Scenario(bots: [bot(stopAfter: .seconds(1), stopWhenOthersStopped: true)], stopsRequired: 2)
        s.hostAutoPlay = false
        await s.start()
        await s.run("writing") { s.host.state.phase == .writing }
        for _ in 0..<(5 * 4) { await s.step() }
        #expect(s.host.state.currentRound?.stops.isEmpty == true)
        s.host.localClient.send(.giveUp(answers: ["", "", ""]))
        await s.run("bot stopped too") { s.host.state.phase != .writing }
        #expect(s.host.state.currentRound?.stops.map(\.playerID) == [s.hostID, s.id(0)])
    }

    @Test func latency500msStillConverges() async throws {
        let s = try Scenario(bots: [bot(scoreDelay: .milliseconds(300)), bot(scoreDelay: .milliseconds(300))],
                             stopsRequired: 2)
        await s.start()
        s.net.setLatency(.milliseconds(500))
        // In-memory latency is real time: give each 250 ms game-time step 100 ms of real time.
        s.realTimePerStep = .milliseconds(100)
        await s.runToGameOver(seconds: 60)
        #expect(s.host.state.rounds[0].stops.count == 2)
        s.expectConsistentEverywhere()
    }

    @Test func practiceLaunchJoinsBotsAndPersistsNoGame() async throws {
        let clock = TestClock()
        let store = InMemoryGameStore()
        let profile = Profile(playerID: UUID(), name: "Gui", soundsEnabled: false)
        let (host, bots, _) = MockGameLauncher.launch(
            hostProfile: profile, botNames: ["Ana", "Bia"],
            settings: GameSettings(categories: categories, stopsRequired: 1, allowGiveUp: true), language: .en,
            botSpeed: .fast, practice: true, store: store, clock: clock)
        await waitUntil("bots in the lobby") {
            host.state.players.count == 3 && bots.allSatisfy { $0.client.hostStatus == .connected }
        }
        #expect(Set(host.state.players.map(\.name)) == ["Gui", "Ana", "Bia"])
        host.localClient.send(.startGame)
        await waitUntil("bots see the round") { bots.allSatisfy { $0.client.state?.rounds.count == 1 } }
        #expect(await store.loadHostGame() == nil)
        #expect(await store.loadActiveGame() == nil)
        host.shutdown()
    }
}
