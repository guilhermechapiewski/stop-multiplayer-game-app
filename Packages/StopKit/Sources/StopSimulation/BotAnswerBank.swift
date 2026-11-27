import Foundation
import StopCore

/// Bundled per-language word banks the practice bots answer from.
/// JSON shape: `{ "<category>": { "A": ["…"], … } }`, keyed by the `DefaultCategories` strings.
public struct BotAnswerBank: Sendable {
    /// Folded category name → uppercase letter → answers.
    private let entries: [String: [String: [String]]]

    init(entries: [String: [String: [String]]]) {
        var folded: [String: [String: [String]]] = [:]
        for (category, byLetter) in entries {
            folded[Self.fold(category)] = Dictionary(
                byLetter.map { ($0.key.uppercased(), $0.value) },
                uniquingKeysWith: { $0 + $1 })
        }
        self.entries = folded
    }

    public static func load(_ language: GameLanguage) -> BotAnswerBank {
        switch language {
        case .en: english
        case .ptBR: portuguese
        }
    }

    /// Answers for `category` starting with `letter`. Category matching ignores case,
    /// accents and surrounding whitespace; an unknown category yields `[]`.
    public func candidates(category: String, letter: String) -> [String] {
        let key = letter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return entries[Self.fold(category)]?[key] ?? []
    }

    /// Trimmed, case- and diacritic-insensitive form used for comparisons.
    static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static let english = decode("en")
    private static let portuguese = decode("pt-BR")

    private static func decode(_ name: String) -> BotAnswerBank {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "BotAnswers")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: [String: [String]]].self, from: data)
        else {
            assertionFailure("missing or malformed bot answer bank \(name).json")
            return BotAnswerBank(entries: [:])
        }
        return BotAnswerBank(entries: entries)
    }
}
