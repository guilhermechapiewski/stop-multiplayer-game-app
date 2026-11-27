import SwiftUI

/// Explains the current stop and give-up rules in one sentence or two.
enum RulesText {
    static func footer(stopsRequired: Int, allowGiveUp: Bool) -> LocalizedStringKey {
        switch (stopsRequired == 1, allowGiveUp) {
        case (true, false):
            "The round ends as soon as someone fills in every category and taps STOP."
        case (true, true):
            "The round ends as soon as someone taps STOP or gives up."
        case (false, false):
            "The round ends once \(stopsRequired) players have filled in every category and tapped STOP."
        case (false, true):
            "The round ends once \(stopsRequired) players have tapped STOP or given up."
        }
    }

    /// How answers show during scoring: read aloud (the default) or silent.
    static func scoring(silent: Bool) -> LocalizedStringKey {
        silent ? "Silent mode: everyone’s answers show as soon as a category opens."
            : "Read aloud: each answer shows once its player scores it, so read yours out loud first."
    }
}
