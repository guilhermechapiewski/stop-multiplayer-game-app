import SwiftUI

/// First launch: asks for the name friends will see.
struct NameEntryView: View {
    let model: AppModel

    @State private var name = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    private var canContinue: Bool { !PlayerName.isBlank(name) && !isSaving }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                StopSign(size: 112)
                Text("Welcome to \(AppInfo.name)")
                    .font(Theme.Typography.display)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("The classic word game, played with friends nearby.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("What’s your name?")
                    .font(Theme.Typography.headline)
                    .accessibilityHidden(true)
                TextField("Your name", text: $name)
                    .font(Theme.Typography.headline)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($isFocused)
                    .onSubmit(save)
                    .onChange(of: name) { name = PlayerName.limited($1) }
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(minHeight: 56)
                    .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.control))
                    .accessibilityLabel("Your name")
                    .accessibilityHint("Friends see this name when you play together.")
                    .accessibilityIdentifier("nameField")
                Text("Friends see this name when you play together.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Button("Continue", action: save)
                .buttonStyle(.primary)
                .disabled(!canContinue)
                .accessibilityIdentifier("continueButton")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.xl)
        .centeredScrolling()
        .background(Theme.background)
        .task { isFocused = true }
    }

    private func save() {
        guard canContinue else { return }
        isSaving = true
        Task {
            await model.saveName(name)
            isSaving = false
        }
    }
}

/// Display-name rules shared by onboarding and Settings.
enum PlayerName {
    static let maxLength = 20

    static func isBlank(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func limited(_ name: String) -> String {
        name.count > maxLength ? String(name.prefix(maxLength)) : name
    }
}

#Preview {
    NameEntryView(model: PreviewData.model(playerName: nil))
}
