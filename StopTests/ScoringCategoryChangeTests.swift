import Testing
@testable import Stop

struct ScoringCategoryChangeTests {
    typealias Change = ScoringCategoryChange

    @Test func movingOnSlidesFromTheTrailingEdge() {
        #expect(Change.direction(from: 0, to: 1, otherwise: .backward) == .forward)
    }

    @Test func goingBackSlidesFromTheLeadingEdge() {
        #expect(Change.direction(from: 2, to: 1, otherwise: .forward) == .backward)
    }

    /// No change keeps the last direction, so a later update mid-slide doesn't flip it.
    @Test func sameCategoryKeepsTheLastDirection() {
        #expect(Change.direction(from: 1, to: 1, otherwise: .backward) == .backward)
        #expect(Change.direction(from: 1, to: 1, otherwise: .forward) == .forward)
    }

    @Test func completingTheCurrentCategoryCelebrates() {
        let before = Change.Snapshot(categoryIndex: 1, isCompleted: false)
        let after = Change.Snapshot(categoryIndex: 1, isCompleted: true)
        #expect(Change.celebratesCompletion(from: before, to: after))
    }

    /// Going back to (or on to) a category that is already complete isn't a completion.
    @Test func arrivingAtACompletedCategoryDoesNotCelebrate() {
        let before = Change.Snapshot(categoryIndex: 2, isCompleted: false)
        let after = Change.Snapshot(categoryIndex: 1, isCompleted: true)
        #expect(!Change.celebratesCompletion(from: before, to: after))
    }

    @Test func losingOrKeepingCompletionDoesNotCelebrate() {
        let done = Change.Snapshot(categoryIndex: 1, isCompleted: true)
        let open = Change.Snapshot(categoryIndex: 1, isCompleted: false)
        #expect(!Change.celebratesCompletion(from: done, to: open))
        #expect(!Change.celebratesCompletion(from: done, to: done))
    }
}
