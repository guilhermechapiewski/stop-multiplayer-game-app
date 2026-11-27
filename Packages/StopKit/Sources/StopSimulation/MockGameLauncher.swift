import Foundation
import StopCore
import StopNetworking
import StopSession

/// Starts a game on one device: a real `HostSession` for the local player plus bot `ClientSession`s, all on an
/// `InMemoryNetwork` (no Bonjour, no Local Network prompt).
@MainActor public enum MockGameLauncher {
    /// `settings` must be valid and `hostProfile.name` non-blank (the setup screen guarantees both).
    /// `practice` keeps the game and its active-game reference out of `store`, so it is never restored after a
    /// relaunch; `botBehavior` overrides the practice behavior derived from `botSpeed`. A `seed` makes the game
    /// repeatable (screenshots, UI tests): the host draws the same letters and the bots plan the same answers.
    public static func launch(hostProfile: Profile, botNames: [String], settings: GameSettings,
                              language: GameLanguage, botSpeed: BotSpeed = .normal, practice: Bool = true,
                              botBehavior: BotPlayer.Behavior? = nil, seed: UInt64? = nil,
                              store: any GameStore = InMemoryGameStore(),
                              clock: any Clock<Duration> = ContinuousClock())
        -> (host: HostSession, bots: [BotPlayer], network: InMemoryNetwork) {
        let state: GameState
        do {
            state = try GameEngine.newGame(gameID: UUID(), hostID: hostProfile.playerID, hostName: hostProfile.name,
                                           settings: settings, language: language)
        } catch {
            preconditionFailure("MockGameLauncher: invalid settings or host name (\(error))")
        }
        let network = InMemoryNetwork()
        let rng: any RandomNumberGenerator & Sendable = if let seed { SplitMix64(seed: seed) }
                                                        else { SystemRandomNumberGenerator() }
        let host = HostSession(state: state, factory: network, store: practice ? PracticeStore(store) : store,
                               clock: clock, rng: rng)
        host.start()
        let behavior = botBehavior ?? .practice(botSpeed)
        let sharedSeed = seed ?? .random(in: .min ... .max)
        let bots = botNames.enumerated().map { index, name in
            let profile = Profile(playerID: UUID(), name: name, soundsEnabled: false)
            let client = ClientSession(profile: profile, target: .rejoin(gameID: state.gameID), factory: network,
                                       store: InMemoryGameStore(), clock: clock)
            let botSeed = seed.map { $0 &+ UInt64(index + 1) } ?? .random(in: .min ... .max)
            let bot = BotPlayer(name: name, client: client, behavior: behavior, clock: clock, seed: botSeed,
                                index: index, sharedSeed: sharedSeed)
            bot.run()
            client.start()
            return bot
        }
        return (host, bots, network)
    }
}

/// Reads and writes the profile and custom categories through to `base`; keeps the game, the active-game
/// reference and drafts in memory only.
actor PracticeStore: GameStore {
    private let base: any GameStore
    private let memory = InMemoryGameStore()

    init(_ base: any GameStore) { self.base = base }

    func loadProfile() async -> Profile? { await base.loadProfile() }
    func saveProfile(_ p: Profile) async { await base.saveProfile(p) }
    func loadCustomCategories() async -> [String] { await base.loadCustomCategories() }
    func saveCustomCategories(_ c: [String]) async { await base.saveCustomCategories(c) }
    func loadHostGame() async -> GameState? { await memory.loadHostGame() }
    func saveHostGame(_ s: GameState?) async { await memory.saveHostGame(s) }
    func loadActiveGame() async -> ActiveGameRef? { await memory.loadActiveGame() }
    func saveActiveGame(_ r: ActiveGameRef?) async { await memory.saveActiveGame(r) }
    func loadDraft(gameID: UUID, round: Int) async -> [String]? { await memory.loadDraft(gameID: gameID, round: round) }
    func saveDraft(_ a: [String], gameID: UUID, round: Int) async { await memory.saveDraft(a, gameID: gameID, round: round) }
    func clearDrafts(gameID: UUID) async { await memory.clearDrafts(gameID: gameID) }
}
