import StopCore
import SwiftUI

/// One category's answer. Its text lives in this view's own state, so a keystroke re-renders only this field;
/// each change is handed to the (non-observable) `WritingModel`. Return moves to the next field.
struct AnswerField: View {
    let model: WritingModel
    let index: Int
    let category: String
    let isLast: Bool
    /// Shown, read-only, instead of the typed text once the answers are frozen (STOP, give up or the lock).
    let frozenText: String?
    var focus: FocusState<Int?>.Binding

    @State private var text: String

    init(model: WritingModel, index: Int, category: String, isLast: Bool, frozenText: String?,
         focus: FocusState<Int?>.Binding) {
        self.model = model
        self.index = index
        self.category = category
        self.isLast = isLast
        self.frozenText = frozenText
        self.focus = focus
        _text = State(initialValue: model.text(at: index))
    }

    private var isFrozen: Bool { frozenText != nil }
    private var isFilled: Bool { !AnswerText.isBlank(frozenText ?? text) }
    private var isFocused: Bool { focus.wrappedValue == index }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(verbatim: category)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isFocused ? Theme.accent : .secondary)
                Spacer(minLength: 0)
                Image(systemName: isFilled ? "checkmark.circle.fill" : "circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isFilled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .accessibilityHidden(true)

            Group {
                if let frozenText {
                    Text(verbatim: frozenText.isEmpty ? "—" : frozenText)
                        .foregroundStyle(frozenText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(Text(verbatim: category))
                        .accessibilityValue(frozenText.isEmpty ? Text("Blank") : Text(verbatim: frozenText))
                } else {
                    TextField(text: $text) { Text(verbatim: category) }
                        .focused(focus, equals: index)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(isLast ? .done : .next)
                        .onSubmit { focus.wrappedValue = isLast ? nil : index + 1 }
                        .onChange(of: text) { _, newValue in model.update(index: index, text: newValue) }
                        .accessibilityLabel(Text(verbatim: category))
                }
            }
            .font(Theme.Typography.headline)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 52)
            .background(isFrozen ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(Theme.surface),
                        in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isFocused ? Theme.accent : Color.clear, lineWidth: 2)
            }
            .contentShape(.rect)
            .onTapGesture { if !isFrozen { focus.wrappedValue = index } }
            .accessibilityIdentifier("answerField-\(index)")
        }
    }
}

#Preview("Answer fields") {
    @Previewable @FocusState var focus: Int?
    let model = WritingModel(categoryCount: 3, client: PreviewData.client(isHost: true, phase: .writing),
                             initial: ["Bear", "", ""])
    VStack(spacing: Theme.Spacing.m) {
        AnswerField(model: model, index: 0, category: "Animal", isLast: false, frozenText: nil, focus: $focus)
        AnswerField(model: model, index: 1, category: "Country", isLast: false, frozenText: nil, focus: $focus)
        AnswerField(model: model, index: 2, category: "Fruit", isLast: true, frozenText: "", focus: $focus)
    }
    .padding()
    .background(Theme.background)
}
