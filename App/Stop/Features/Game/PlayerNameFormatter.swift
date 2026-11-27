import StopCore

/// Names as shown on screen. The engine keys players by ID, so two friends can both be "Ana"; the second
/// to join shows as "Ana 2", the third as "Ana 3", and so on (case-insensitively, skipping taken names).
enum PlayerNameFormatter {
    static func displayNames(for players: [Player]) -> [PlayerID: String] {
        var taken = Set(players.map { key($0.name) })
        var seen = Set<String>()
        var names: [PlayerID: String] = [:]
        for player in players {
            let base = player.name
            if seen.insert(key(base)).inserted {
                names[player.id] = base
                continue
            }
            var suffix = 2
            while taken.contains(key("\(base) \(suffix)")) { suffix += 1 }
            let name = "\(base) \(suffix)"
            taken.insert(key(name))
            names[player.id] = name
        }
        return names
    }

    private static func key(_ name: String) -> String { name.lowercased() }
}

extension GameState {
    /// Every player's on-screen name (see `PlayerNameFormatter`).
    var displayNames: [PlayerID: String] { PlayerNameFormatter.displayNames(for: players) }
}
