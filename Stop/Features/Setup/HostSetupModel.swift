import Foundation
import Observation
import StopCore
import StopSession

/// The game options the host picks before creating a game (also used by practice setup): which categories,
/// in what order, how many stops end a round and whether giving up counts.
@MainActor @Observable
final class HostSetupModel {
    /// How many of the built-in categories start selected.
    static let defaultSelectionCount = 6
    /// Longest category name accepted.
    static let maxCategoryLength = 30

    /// Every category on offer: the built-in ones for the language, then the remembered custom ones.
    private(set) var available: [String]
    /// The categories the game will use, in play order.
    private(set) var selected: [String]
    var stopsRequired = 1 {
        didSet { if stopsRequired < 1 { stopsRequired = 1 } }
    }
    var allowGiveUp = false
    /// Off: read-aloud scoring (answers show as each player scores their own). On: every answer shows at once.
    var silentScoring = false

    @ObservationIgnored private let store: any GameStore
    @ObservationIgnored private let defaults: [String]
    private var custom: [String] = []
    @ObservationIgnored private var isLoaded = false
    /// The player changed the selection: loading must not replace it with the last game's categories.
    @ObservationIgnored private var hasEditedSelection = false

    init(store: any GameStore, language: GameLanguage) {
        self.store = store
        defaults = DefaultCategories.list(for: language)
        available = defaults
        selected = Array(defaults.prefix(Self.defaultSelectionCount))
    }

    /// Adds the custom categories remembered on this device, keeping any added while they were loading, and
    /// selects the last hosted game's categories (in their order) that are still on offer, unless the
    /// selection was already changed. With fewer than half of them left (none, say), the defaults stay
    /// selected: a few leftovers aren't the last game.
    func load() async {
        let saved = await store.loadCustomCategories()
        let last = await store.loadLastCategories()
        var merged: [String] = []
        for name in saved + custom where !(defaults + merged).contains(where: { Self.same($0, name) }) {
            merged.append(name)
        }
        custom = merged
        isLoaded = true
        rebuildAvailable()
        guard !hasEditedSelection else { return }
        var distinctLast: [String] = []
        for name in last where !distinctLast.contains(where: { Self.same($0, name) }) { distinctLast.append(name) }
        var remembered: [String] = []
        for name in distinctLast {
            guard let match = available.first(where: { Self.same($0, name) }), !remembered.contains(match) else {
                continue
            }
            remembered.append(match)
        }
        if !remembered.isEmpty, remembered.count * 2 >= distinctLast.count { selected = remembered }
    }

    var canCreate: Bool { !selected.isEmpty }

    func isSelected(_ category: String) -> Bool { selected.contains(category) }

    func isCustom(_ category: String) -> Bool { custom.contains(category) }

    /// Selects a category (appending it to the play order) or deselects it.
    func toggle(_ category: String) {
        hasEditedSelection = true
        if let index = selected.firstIndex(of: category) {
            selected.remove(at: index)
        } else if available.contains(category) {
            selected.append(category)
        }
    }

    /// Trims `name`, remembers it for future games and selects it. A name that's already on offer (ignoring
    /// case) just gets selected.
    func addCustom(_ name: String) async {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxCategoryLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasEditedSelection = true
        if let existing = available.first(where: { Self.same($0, trimmed) }) {
            if !isSelected(existing) { selected.append(existing) }
            return
        }
        custom.append(trimmed)
        rebuildAvailable()
        selected.append(trimmed)
        // Never save over the remembered list before it has been read.
        if !isLoaded { await load() }
        await store.saveCustomCategories(custom)
    }

    /// Forgets a remembered custom category.
    func deleteCustom(_ name: String) async {
        // Never save over the remembered list before it has been read (it may hold `name` too).
        if !isLoaded { await load() }
        guard let index = custom.firstIndex(of: name) else { return }
        custom.remove(at: index)
        selected.removeAll { $0 == name }
        rebuildAvailable()
        await store.saveCustomCategories(custom)
    }

    /// Reorders the selected categories.
    func move(from source: IndexSet, to destination: Int) {
        hasEditedSelection = true
        selected.move(fromOffsets: source, toOffset: destination)
    }

    func settings() -> GameSettings {
        GameSettings(categories: selected, stopsRequired: stopsRequired, allowGiveUp: allowGiveUp,
                     silentScoring: silentScoring)
    }

    private func rebuildAvailable() { available = defaults + custom }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive]) == .orderedSame
    }
}
