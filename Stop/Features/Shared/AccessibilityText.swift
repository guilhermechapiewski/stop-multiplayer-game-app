import Foundation
import StopCore

/// VoiceOver strings shared by several views, kept pure so they can be tested (in any app language through
/// `locale`).
enum AccessibilityText {
    /// "10 points" / "1 point": a score button, a standings row, a category result.
    static func score(_ points: Int, locale: Locale = .current) -> String {
        String(localized: LocalizedStringResource("\(points) points", locale: locale))
    }

    /// "Letter B": the round's letter, announced when the reveal lands.
    static func letter(_ letter: String, locale: Locale = .current) -> String {
        String(localized: LocalizedStringResource("Letter \(letter)", locale: locale))
    }

    /// The details read after a player's name on a chip: "Host, You", "Bot, Reconnecting", or nothing.
    static func playerDetails(presence: Presence, isHost: Bool, isYou: Bool, isBot: Bool,
                              locale: Locale = .current) -> String {
        var parts: [LocalizedStringResource] = []
        if isBot { parts.append(LocalizedStringResource("Bot", locale: locale)) }
        if isHost { parts.append(LocalizedStringResource("Host", locale: locale)) }
        if isYou { parts.append(LocalizedStringResource("You", locale: locale)) }
        if presence == .away { parts.append(LocalizedStringResource("Reconnecting", locale: locale)) }
        // Commas, not "and": VoiceOver pauses at each one, and they read the same in every language.
        return parts.map { String(localized: $0) }.joined(separator: ", ")
    }
}
