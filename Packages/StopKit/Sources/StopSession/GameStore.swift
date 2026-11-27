import Foundation
import StopCore

public struct Profile: Codable, Sendable, Equatable {
    public var playerID: PlayerID
    public var name: String
    public var soundsEnabled: Bool
    public init(playerID: PlayerID, name: String, soundsEnabled: Bool) {
        self.playerID = playerID
        self.name = name
        self.soundsEnabled = soundsEnabled
    }
}

public struct ActiveGameRef: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case host, client }
    public var gameID: UUID
    public var role: Role
    public var hostName: String
    /// A `-mockGame` game against bots (UI tests, screenshots): only a mock-mode launch may restore it.
    public var isMock: Bool

    public init(gameID: UUID, role: Role, hostName: String, isMock: Bool = false) {
        self.gameID = gameID
        self.role = role
        self.hostName = hostName
        self.isMock = isMock
    }

    private enum CodingKeys: String, CodingKey { case gameID, role, hostName, isMock }

    /// References saved before `isMock` existed decode as real games.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try container.decode(UUID.self, forKey: .gameID)
        role = try container.decode(Role.self, forKey: .role)
        hostName = try container.decode(String.self, forKey: .hostName)
        isMock = try container.decodeIfPresent(Bool.self, forKey: .isMock) ?? false
    }
}

public protocol GameStore: Sendable {
    func loadProfile() async -> Profile?
    func saveProfile(_ p: Profile) async
    func loadCustomCategories() async -> [String]
    func saveCustomCategories(_ c: [String]) async
    func loadHostGame() async -> GameState?
    func saveHostGame(_ s: GameState?) async
    func loadActiveGame() async -> ActiveGameRef?
    func saveActiveGame(_ r: ActiveGameRef?) async
    func loadDraft(gameID: UUID, round: Int) async -> [String]?
    func saveDraft(_ a: [String], gameID: UUID, round: Int) async
    func clearDrafts(gameID: UUID) async
}

public actor InMemoryGameStore: GameStore {
    private var profile: Profile?
    private var categories: [String] = []
    private var hostGame: GameState?
    private var activeGame: ActiveGameRef?
    private var drafts: [String: [String]] = [:]

    public init() {}

    public func loadProfile() -> Profile? { profile }
    public func saveProfile(_ p: Profile) { profile = p }
    public func loadCustomCategories() -> [String] { categories }
    public func saveCustomCategories(_ c: [String]) { categories = c }
    public func loadHostGame() -> GameState? { hostGame }
    public func saveHostGame(_ s: GameState?) { hostGame = s }
    public func loadActiveGame() -> ActiveGameRef? { activeGame }
    public func saveActiveGame(_ r: ActiveGameRef?) { activeGame = r }
    public func loadDraft(gameID: UUID, round: Int) -> [String]? { drafts["\(gameID.uuidString)-\(round)"] }
    public func saveDraft(_ a: [String], gameID: UUID, round: Int) { drafts["\(gameID.uuidString)-\(round)"] = a }
    public func clearDrafts(gameID: UUID) { drafts = drafts.filter { !$0.key.hasPrefix(gameID.uuidString + "-") } }
}
