// Practice with bots exists only in Debug builds (owner decision, 2026-11-27); Release builds leave it out.
#if DEBUG
import Foundation
import Observation
import StopCore
import StopSession
import StopSimulation

/// The options for a practice game: the shared game options (categories, stops, giving up) plus how many bots
/// play and how fast they are.
@MainActor @Observable
final class PracticeSetupModel {
    static let botRange = 1...5
    static let defaultBotCount = 3

    /// Categories, stops required and giving up, as in host setup.
    let setup: HostSetupModel
    var botCount = PracticeSetupModel.defaultBotCount {
        didSet {
            let clamped = min(max(botCount, Self.botRange.lowerBound), Self.botRange.upperBound)
            if botCount != clamped { botCount = clamped }
            // Every bot plus the player can stop; asking for more would make rounds impossible to end.
            if setup.stopsRequired > maxStops { setup.stopsRequired = maxStops }
        }
    }
    var speed: BotSpeed = .normal

    @ObservationIgnored private let language: GameLanguage

    init(store: any GameStore, language: GameLanguage) {
        self.language = language
        setup = HostSetupModel(store: store, language: language)
    }

    /// The bots that will play, in joining order.
    var botNames: [String] { Array(Self.botNames(for: language).prefix(botCount)) }

    /// Most stops a round can need: every bot plus the player.
    var maxStops: Int { botCount + 1 }

    var canStart: Bool { setup.canCreate }

    /// Bots only know the built-in categories: in custom ones they guess and honestly score themselves 0.
    var hasCustomCategories: Bool { setup.selected.contains(where: setup.isCustom) }

    func settings() -> GameSettings { setup.settings() }

    /// Whether a display name (possibly with a duplicate suffix, "Robo Ana 2") is a practice bot's.
    nonisolated static func isBotName(_ name: String) -> Bool {
        name.hasPrefix("Robo ") || name.hasPrefix("Robô ")
    }

    /// Bot names for each language, always in this order (a game with two bots gets the first two).
    static func botNames(for language: GameLanguage) -> [String] {
        switch language {
        case .en: ["Robo Ana", "Robo Ben", "Robo Cris", "Robo Dani", "Robo Edu"]
        case .ptBR: ["Robô Ana", "Robô Beto", "Robô Cris", "Robô Dani", "Robô Edu"]
        }
    }
}
#endif
