import StopCore
import StopSession
import SwiftUI

/// The round's letter being drawn: letters spin past, slow down and land on the letter. The host's ticks
/// move the game on to the countdown, so it waits for an away host by itself.
struct LetterRevealView: View {
    let round: Round

    @Environment(\.reduceMotion) private var reduceMotion
    @State private var shown: String?
    @State private var landed = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("Round \(round.number)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.secondary)
                Text(landed ? "The letter is…" : "Picking a letter…")
                    .font(Theme.Typography.title)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            LetterTile(letter: shown ?? " ", size: 168)
                .keyframeAnimator(initialValue: 1.0, trigger: landed) { tile, scale in
                    tile.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(reduceMotion ? 1 : 1.18, duration: 0.15)
                        SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                    }
                }
                .opacity(shown == nil ? 0 : 1)
                .accessibilityHidden(!landed)
                .accessibilityLabel(Text("Letter \(round.letter)"))
                .accessibilityIdentifier("revealedLetter")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
        .task(id: round.number) { await spin() }
    }

    private func spin() async {
        guard !reduceMotion else {
            withAnimation(.easeIn(duration: 0.4)) { land() }
            return
        }
        let alphabet = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
            .compactMap(UnicodeScalar.init).map(String.init).filter { $0 != round.letter }
        // Fast at first, easing out: about 1.3 s in all, well inside the 2-tick reveal.
        for step in 0..<16 {
            shown = alphabet.randomElement()
            let delay = 30 + step * step * 2
            do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
        }
        land()
    }

    private func land() {
        shown = round.letter
        landed = true
        GameFeedback.play(.letterRevealed)
        AccessibilityNotification.Announcement(String(localized: "Letter \(round.letter)")).post()
    }
}

/// The round's letter on an accent tile.
struct LetterTile: View {
    let letter: String
    var size: CGFloat = 120

    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.4)
        Text(verbatim: letter)
            .font(.system(size: side * 0.62, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .contentTransition(.identity)
            .frame(width: side, height: side)
            .background(Theme.accent.gradient, in: .rect(cornerRadius: side * 0.24))
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.2)
                    .inset(by: side * 0.05)
                    .strokeBorder(.white.opacity(0.5), lineWidth: max(1.5, side * 0.02))
            }
            .shadow(color: Theme.accent.opacity(0.3), radius: side * 0.08, y: side * 0.04)
    }
}

#Preview("Letter reveal") {
    LetterRevealView(round: Round(number: 2, letter: "B", participants: []))
        .background(Theme.background)
}

#Preview("Letter reveal – reduce motion") {
    LetterRevealView(round: Round(number: 2, letter: "M", participants: []))
        .background(Theme.background)
        .environment(\.reduceMotion, true)
}
