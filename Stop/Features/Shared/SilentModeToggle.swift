import SwiftUI

/// The host's "Silent mode" switch for scoring, with an ⓘ button that explains the two modes. Used in setup,
/// the lobby and the round results.
struct SilentModeToggle: View {
    @Binding var isOn: Bool
    var identifier = "silentModeToggle"

    @State private var showsInfo = false

    var body: some View {
        // The info button sits beside the label, outside the switch, so VoiceOver reads them as two controls.
        HStack(spacing: Theme.Spacing.xs) {
            Text("Silent mode")
                .accessibilityHidden(true)
            Button { showsInfo = true } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.accent)
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("About silent mode"))
            .accessibilityIdentifier("silentModeInfoButton")
            .popover(isPresented: $showsInfo) { SilentModeInfo() }
            Spacer(minLength: Theme.Spacing.s)
            Toggle(isOn: $isOn) { Text("Silent mode") }
                .labelsHidden()
                .accessibilityIdentifier(identifier)
        }
    }
}

/// What read-aloud and silent scoring mean, in a popover that grows with the text size.
struct SilentModeInfo: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Read aloud (default): answers stay hidden until each person scores their own, so everyone reads theirs out loud first.")
                Text("Silent mode: everyone’s answers show right away, for playing without talking.")
            }
            .font(Theme.Typography.body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(idealWidth: 320, maxHeight: 420)
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.surface)
        .presentationCompactAdaptation(.popover)
        .accessibilityIdentifier("silentModeInfo")
    }
}

#Preview("Silent mode toggle") {
    @Previewable @State var on = false
    List { SilentModeToggle(isOn: $on) }
}
