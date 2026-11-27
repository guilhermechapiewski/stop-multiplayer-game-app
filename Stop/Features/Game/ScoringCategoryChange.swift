/// How the scoring screen reacts when the category or its completion changes: which way the answers card slides,
/// and whether to celebrate (haptic and completion animation). Pure, so it's unit tested.
enum ScoringCategoryChange {
    enum Direction: Equatable {
        /// Next category: the new card slides in from the trailing edge.
        case forward
        /// Previous category: the new card slides in from the leading edge.
        case backward
    }

    /// What the screen showed, compared before and after an update.
    struct Snapshot: Equatable {
        var categoryIndex: Int
        var isCompleted: Bool
    }

    /// The direction of a move from category `old` to `new`; `otherwise` (the last direction) when it didn't
    /// move, so a later update during the slide doesn't flip it.
    static func direction(from old: Int, to new: Int, otherwise: Direction) -> Direction {
        if new > old { return .forward }
        if new < old { return .backward }
        return otherwise
    }

    /// Only finishing the category on screen celebrates. Arriving at a category that is already complete (the
    /// host went back, or moved on to one everyone had scored) is not a completion.
    static func celebratesCompletion(from old: Snapshot, to new: Snapshot) -> Bool {
        new.isCompleted && !old.isCompleted && new.categoryIndex == old.categoryIndex
    }
}
