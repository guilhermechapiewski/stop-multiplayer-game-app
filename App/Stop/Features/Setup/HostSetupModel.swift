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

    @ObservationIgnored private let store: any GameStore
    @ObservationIgnored private let defaults: [String]
    private var custom: [String] = []

    init(store: any GameStore, language: GameLanguage) {
        self.store = store
        defaults = DefaultCategories.list(for: language)
        available = defaults
        selected = Array(defaults.prefix(Self.defaultSelectionCount))
    }

    /// Adds the custom categories remembered on this device.
    func load() async {
        let saved = await store.loadCustomCategories()
        custom = saved.filter { name in !defaults.contains { Self.same($0, name) } }
        rebuildAvailable()
    }

    var canCreate: Bool { !selected.isEmpty }

    func isSelected(_ category: String) -> Bool { selected.contains(category) }

    func isCustom(_ category: String) -> Bool { custom.contains(category) }

    /// Selects a category (appending it to the play order) or deselects it.
    func toggle(_ category: String) {
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
        guard !trimmed.isEmpty else { return }
        if let existing = available.first(where: { Self.same($0, trimmed) }) {
            if !isSelected(existing) { selected.append(existing) }
            return
        }
        custom.append(trimmed)
        rebuildAvailable()
        selected.append(trimmed)
        await store.saveCustomCategories(custom)
    }

    /// Forgets a remembered custom category.
    func deleteCustom(_ name: String) async {
        guard let index = custom.firstIndex(of: name) else { return }
        custom.remove(at: index)
        selected.removeAll { $0 == name }
        rebuildAvailable()
        await store.saveCustomCategories(custom)
    }

    /// Reorders the selected categories.
    func move(from source: IndexSet, to destination: Int) {
        selected.move(fromOffsets: source, toOffset: destination)
    }

    func settings() -> GameSettings {
        GameSettings(categories: selected, stopsRequired: stopsRequired, allowGiveUp: allowGiveUp)
    }

    private func rebuildAvailable() { available = defaults + custom }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive]) == .orderedSame
    }
}
