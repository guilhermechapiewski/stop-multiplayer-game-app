import Foundation
import StopCore
import Testing
@testable import StopSession

struct FileGameStoreTests {
    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("stop-store-\(UUID().uuidString)")
    }

    @Test func fileStorePersistsAcrossInstances() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let profile = Profile(playerID: UUID(), name: "Ana", soundsEnabled: false)
        let game = WireMessageTests.state
        let ref = ActiveGameRef(gameID: game.gameID, role: .host, hostName: "Ana")
        let a = FileGameStore(directory: dir)
        await a.saveProfile(profile)
        await a.saveCustomCategories(["Cor", "Fruta"])
        await a.saveHostGame(game)
        await a.saveActiveGame(ref)
        await a.saveDraft(["x", "y"], gameID: game.gameID, round: 1)

        let b = FileGameStore(directory: dir)
        #expect(await b.loadProfile() == profile)
        #expect(await b.loadCustomCategories() == ["Cor", "Fruta"])
        #expect(await b.loadHostGame() == game)
        #expect(await b.loadActiveGame() == ref)
        #expect(await b.loadDraft(gameID: game.gameID, round: 1) == ["x", "y"])

        await b.saveHostGame(nil)
        await b.saveActiveGame(nil)
        #expect(await FileGameStore(directory: dir).loadHostGame() == nil)
        #expect(await FileGameStore(directory: dir).loadActiveGame() == nil)
    }

    /// A reference saved before `isMock` existed is a real game; a mock one round-trips its flag.
    @Test func activeGameRefMockFlag() throws {
        let id = UUID()
        let old = #"{"gameID":"\#(id.uuidString)","role":"host","hostName":"Ana"}"#
        let decoded = try JSONDecoder().decode(ActiveGameRef.self, from: Data(old.utf8))
        #expect(decoded == ActiveGameRef(gameID: id, role: .host, hostName: "Ana"))
        #expect(!decoded.isMock)
        let mock = ActiveGameRef(gameID: id, role: .host, hostName: "Ana", isMock: true)
        #expect(try JSONDecoder().decode(ActiveGameRef.self, from: JSONEncoder().encode(mock)) == mock)
    }

    @Test(arguments: [true, false])
    func draftsKeyedByGameAndRound(file: Bool) async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store: any GameStore = file ? FileGameStore(directory: dir) : InMemoryGameStore()
        let g1 = UUID(), g2 = UUID()
        await store.saveDraft(["r2"], gameID: g1, round: 2)
        await store.saveDraft(["r1"], gameID: g1, round: 1)
        await store.saveDraft(["other"], gameID: g2, round: 2)
        #expect(await store.loadDraft(gameID: g1, round: 2) == ["r2"])
        #expect(await store.loadDraft(gameID: g1, round: 3) == nil)
        await store.clearDrafts(gameID: g1)
        #expect(await store.loadDraft(gameID: g1, round: 1) == nil)
        #expect(await store.loadDraft(gameID: g1, round: 2) == nil)
        #expect(await store.loadDraft(gameID: g2, round: 2) == ["other"])
    }

    /// The last hosted game's categories, in order; nothing saved reads as empty.
    @Test(arguments: [true, false])
    func lastCategoriesRoundTrip(file: Bool) async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store: any GameStore = file ? FileGameStore(directory: dir) : InMemoryGameStore()
        #expect(await store.loadLastCategories().isEmpty)
        await store.saveLastCategories(["Fruta", "Cartoons", "Nome"])
        #expect(await store.loadLastCategories() == ["Fruta", "Cartoons", "Nome"])
        await store.saveLastCategories(["Animal"])
        #expect(await store.loadLastCategories() == ["Animal"])
        if file { #expect(await FileGameStore(directory: dir).loadLastCategories() == ["Animal"]) }
    }

    @Test func corruptFileLoadsAsNil() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileGameStore(directory: dir)
        await store.saveHostGame(WireMessageTests.state)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("hostGame.json"))
        #expect(await store.loadHostGame() == nil)
    }
}
