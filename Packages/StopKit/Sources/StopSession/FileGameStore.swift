import Foundation
import StopCore

/// One JSON file per key in `directory`; writes are atomic. Failures are swallowed (best-effort persistence).
public actor FileGameStore: GameStore {
    private let directory: URL
    private let fm = FileManager.default

    public init(directory: URL) {
        self.directory = directory
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name + ".json") }
    private func draftName(_ gameID: UUID, _ round: Int) -> String { "draft-\(gameID.uuidString)-\(round)" }

    private func read<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write(_ value: some Encodable, _ name: String) {
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    private func writeOptional(_ value: (some Encodable)?, _ name: String) {
        if let value { write(value, name) } else { try? fm.removeItem(at: url(name)) }
    }

    public func loadProfile() -> Profile? { read("profile") }
    public func saveProfile(_ p: Profile) { write(p, "profile") }
    public func loadCustomCategories() -> [String] { read("categories") ?? [] }
    public func saveCustomCategories(_ c: [String]) { write(c, "categories") }
    public func loadHostGame() -> GameState? { read("hostGame") }
    public func saveHostGame(_ s: GameState?) { writeOptional(s, "hostGame") }
    public func loadActiveGame() -> ActiveGameRef? { read("activeGame") }
    public func saveActiveGame(_ r: ActiveGameRef?) { writeOptional(r, "activeGame") }
    public func loadDraft(gameID: UUID, round: Int) -> [String]? { read(draftName(gameID, round)) }
    public func saveDraft(_ a: [String], gameID: UUID, round: Int) { write(a, draftName(gameID, round)) }

    public func clearDrafts(gameID: UUID) {
        let prefix = "draft-\(gameID.uuidString)-"
        let files = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        for f in files where f.hasPrefix(prefix) { try? fm.removeItem(at: directory.appendingPathComponent(f)) }
    }
}
