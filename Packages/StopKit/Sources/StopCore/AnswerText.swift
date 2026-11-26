import Foundation

public enum AnswerText {
    /// True when the text is empty after trimming whitespace and newlines.
    public static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
