import StopCore

/// What the scoring screen shows for the open category, as seen by `viewer`.
struct ScoringPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let playerID: PlayerID
        let name: String
        /// "—" when blank or missing.
        let answer: String
        /// Blank (whitespace only) or missing: fixed at 0.
        let isBlank: Bool
        let score: Int?
        let presence: Presence

        var id: PlayerID { playerID }
    }

    let categoryName: String
    let categoryIndex: Int
    let total: Int
    /// The round's participants, in join order.
    let rows: [Row]
    let myScore: Int?
    let myAnswerIsBlank: Bool
    /// Away or left participants the host may still score for (empty for everyone but the host).
    let canHostScore: Set<PlayerID>
    /// Every active participant has a score; picks stay editable until the host moves on.
    let isCompleted: Bool
    /// The open category is the round's last: moving on shows the results.
    let isLastCategory: Bool
    /// The viewer is the host, who moves everyone on to the next category.
    let showsAdvanceButton: Bool
    /// The host's display name, for "Waiting for Gui to continue…".
    let hostName: String

    /// The host can move on now.
    var canAdvance: Bool { showsAdvanceButton && isCompleted }

    static let blankAnswer = "—"

    init(state: GameState, viewer: PlayerID) {
        let round = state.currentRound
        let index: Int
        if case .scoring(let category, let completed) = state.phase {
            index = category
            isCompleted = completed
        } else {
            index = 0
            isCompleted = false
        }
        let categories = state.settings.categories
        categoryIndex = index
        categoryName = categories.indices.contains(index) ? categories[index] : ""
        total = categories.count
        isLastCategory = index == categories.count - 1
        showsAdvanceButton = viewer == state.hostID

        let names = state.displayNames
        hostName = names[state.hostID] ?? state.player(state.hostID)?.name ?? ""
        let participants = Set(round?.participants ?? [])
        func answer(_ id: PlayerID) -> String? {
            guard let answers = round?.answers[id], answers.indices.contains(index) else { return nil }
            return answers[index]
        }
        func isBlank(_ id: PlayerID) -> Bool { answer(id).map(AnswerText.isBlank) ?? true }
        func score(_ id: PlayerID) -> Int? {
            guard let scores = round?.scores[id], scores.indices.contains(index) else { return nil }
            return scores[index]
        }
        rows = state.players.filter { participants.contains($0.id) }.map { player in
            let blank = isBlank(player.id)
            return Row(playerID: player.id, name: names[player.id] ?? player.name,
                       answer: blank ? Self.blankAnswer : answer(player.id) ?? "", isBlank: blank,
                       score: score(player.id), presence: player.presence)
        }
        myScore = participants.contains(viewer) ? score(viewer) : nil
        myAnswerIsBlank = isBlank(viewer)
        canHostScore = viewer == state.hostID
            ? Set(rows.filter { [.away, .left].contains($0.presence) && $0.score == nil && $0.playerID != viewer }
                .map(\.playerID))
            : []
    }
}
