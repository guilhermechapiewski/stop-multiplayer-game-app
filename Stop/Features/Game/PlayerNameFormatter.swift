import StopCore

/// Names as shown on screen. The engine keys players by ID, so two friends can both be "Ana"; the second
/// to join shows as "Ana 2", the third as "Ana 3", and so on (case-insensitively, skipping taken names).
enum PlayerNameFormatter {
    static func displayNames(for players: [Player]) -> [PlayerID: String] {
        Dictionary(uniqueKeysWithValues: zip(players.map(\.id), disambiguated(players.map(\.name))))
    }

    /// `names` in the same order, with a suffix on every repeat after the first.
    static func disambiguated(_ names: [String]) -> [String] {
        var taken = Set(names.map(key))
        var seen = Set<String>()
        return names.map { base in
            if seen.insert(key(base)).inserted { return base }
            var suffix = 2
            while taken.contains(key("\(base) \(suffix)")) { suffix += 1 }
            let name = "\(base) \(suffix)"
            taken.insert(key(name))
            return name
        }
    }

    private static func key(_ name: String) -> String { name.lowercased() }
}

extension GameState {
    /// Every player's on-screen name (see `PlayerNameFormatter`).
    var displayNames: [PlayerID: String] { PlayerNameFormatter.displayNames(for: players) }
}
