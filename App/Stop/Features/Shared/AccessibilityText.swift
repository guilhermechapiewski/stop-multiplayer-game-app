import Foundation
import StopCore

/// VoiceOver strings shared by several views, kept pure so they can be tested.
enum AccessibilityText {
    /// "10 points": a score button, a standings row, a category result.
    static func score(_ points: Int) -> String {
        String(localized: "\(points) points")
    }

    /// "Letter B": the round's letter, announced when the reveal lands.
    static func letter(_ letter: String) -> String {
        String(localized: "Letter \(letter)")
    }

    /// The details read after a player's name on a chip: "Host, You", "Bot, Reconnecting", or nothing.
    static func playerDetails(presence: Presence, isHost: Bool, isYou: Bool, isBot: Bool) -> String {
        var parts: [String] = []
        if isBot { parts.append(String(localized: "Bot")) }
        if isHost { parts.append(String(localized: "Host")) }
        if isYou { parts.append(String(localized: "You")) }
        if presence == .away { parts.append(String(localized: "Reconnecting")) }
        // Commas, not "and": VoiceOver pauses at each one, and they read the same in every language.
        return parts.joined(separator: ", ")
    }
}
