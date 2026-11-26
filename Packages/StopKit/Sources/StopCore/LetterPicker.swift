public enum LetterPicker {
    public static let alphabet: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }

    /// Picks a letter not yet used; once all 26 are used, starts over.
    public static func pick(used: [String], using rng: inout some RandomNumberGenerator) -> (letter: String, used: [String]) {
        let base = used.count >= alphabet.count ? [] : used
        let letter = alphabet.filter { !base.contains($0) }.randomElement(using: &rng) ?? alphabet[0]
        return (letter, base + [letter])
    }
}
