import Observation
import StopCore
import StopSession

/// The answers being typed this round. Deliberately not observable: a keystroke updates only its own field's
/// view state and this plain store (plus a debounced draft save), never anything a view depends on. The one
/// observable bit is `availability`, which changes only when "every category is filled" flips.
@MainActor final class WritingModel {
    let availability = StopAvailability()

    private let client: any GameClient
    private(set) var answers: [String]

    /// `initial` (a restored draft) is padded or trimmed to `categoryCount`.
    init(categoryCount: Int, client: any GameClient, initial: [String]?) {
        self.client = client
        answers = Array(((initial ?? []) + Array(repeating: "", count: categoryCount)).prefix(categoryCount))
        availability.allFilled = allFilled
    }

    var allFilled: Bool { !answers.contains(where: AnswerText.isBlank) }

    func text(at index: Int) -> String { answers.indices.contains(index) ? answers[index] : "" }

    /// Stores the text locally and saves the draft (the session debounces it, off the main thread).
    func update(index: Int, text: String) {
        guard answers.indices.contains(index), answers[index] != text else { return }
        answers[index] = text
        client.saveDraft(answers)
        let filled = allFilled
        if availability.allFilled != filled { availability.allFilled = filled }
    }

    func stop() { client.send(.stop(answers: answers)) }

    /// Blank answers are allowed when giving up.
    func giveUp() { client.send(.giveUp(answers: answers)) }
}

/// Whether STOP can be tapped. Written only when the value flips, so only the STOP button re-renders.
@MainActor @Observable final class StopAvailability {
    var allFilled = false
}
