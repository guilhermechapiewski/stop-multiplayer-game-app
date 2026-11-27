public enum LetterPicker {
    public static let alphabet: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }

    /// Picks a letter not yet used; once all 26 are used, starts over.
    public static func pick(used: [String], using rng: inout some RandomNumberGenerator) -> (letter: String, used: [String]) {
        let base = used.count >= alphabet.count ? [] : used
        let letter = alphabet.filter { !base.contains($0) }.randomElement(using: &rng) ?? alphabet[0]
        return (letter, base + [letter])
    }

    /// Swaps `current` (the last letter in `used`) for another one not yet used: `current` goes back to the
    /// pool but is never picked again here. With no other letter left, the pool starts over as in `pick`,
    /// still without `current`.
    public static func reroll(current: String, used: [String],
                              using rng: inout some RandomNumberGenerator) -> (letter: String, used: [String]) {
        var base = used.filter { $0 != current }
        var candidates = alphabet.filter { $0 != current && !base.contains($0) }
        if candidates.isEmpty {
            base = []
            candidates = alphabet.filter { $0 != current }
        }
        let letter = candidates.randomElement(using: &rng) ?? alphabet[0]
        return (letter, base + [letter])
    }
}
