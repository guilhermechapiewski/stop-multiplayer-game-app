import Foundation
import StopCore
import StopSession
import SwiftUI

/// The round's letter being drawn: letters spin past, slow down and land on the letter. The host's ticks
/// move the game on to the countdown, so it waits for an away host by itself.
struct LetterRevealView: View {
    let round: Round
    /// Keys the VoiceOver announcement, so a new game's round 1 is announced even with the same letter.
    let gameID: UUID
    /// Host only: draws another letter.
    var onReroll: (() -> Void)?

    @Environment(\.reduceMotion) private var reduceMotion
    @State private var shown: String?
    @State private var landed = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("Round \(round.number)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.secondaryText)
                Text(landed ? "The letter is…" : "Picking a letter…")
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            SunburstTile(letter: shown ?? " ", size: 160)
                .keyframeAnimator(initialValue: 1.0, trigger: landed) { tile, scale in
                    tile.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(reduceMotion ? 1 : 1.18, duration: 0.15)
                        SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                    }
                }
                .opacity(shown == nil ? 0 : 1)
                // One element for the tile and its sunburst, so the label and identifier land only here.
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityHidden(!landed)
                .accessibilityLabel(Text("Letter \(round.letter)"))
                .accessibilityIdentifier("revealedLetter")
            if let onReroll { NewLetterButton(action: onReroll) }
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
        // Fast at first, easing out: about 0.6 s in all, so it lands well inside the 2-tick reveal.
        for step in 0..<11 {
            shown = alphabet.randomElement()
            let delay = 20 + step * step * 7 / 10
            do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
        }
        land()
    }

    private func land() {
        shown = round.letter
        landed = true
        GameFeedback.play(.letterRevealed)
        LetterAnnouncement.announce(round, gameID: gameID)
    }
}

/// Announces the round's letter to VoiceOver once per round of each game: when the reveal lands, or when the
/// countdown appears if the reveal was missed (joined late, app in the background).
@MainActor
enum LetterAnnouncement {
    private struct Key: Equatable {
        let gameID: UUID
        let number: Int
        let letter: String
    }

    private static var announced: Key?

    /// Returns whether it announced (false when this round was already announced).
    @discardableResult
    static func announce(_ round: Round, gameID: UUID) -> Bool {
        let key = Key(gameID: gameID, number: round.number, letter: round.letter)
        guard announced != key else { return false }
        announced = key
        AccessibilityNotification.Announcement(AccessibilityText.letter(round.letter)).post()
        return true
    }
}

/// Host only, on the letter reveal and the countdown: swaps the letter for another one.
struct NewLetterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New letter", systemImage: "dice.fill")
        }
        .buttonStyle(.link)
        .accessibilityHint(Text("Draws another letter for everyone and restarts the countdown."))
        .accessibilityIdentifier("newLetterButton")
    }
}

/// The round's letter as a game tile cut from the icon: a chunky red-orange letter, outlined in dark brown,
/// on a cream tile that stands on a hard edge. The tile is cream in dark mode too, like the icon's bubble.
struct LetterTile: View {
    let letter: String
    var size: CGFloat = 120

    @ScaledMetric private var scale: CGFloat = 1

    /// Light enough throughout for the red letter's 4.5:1.
    static let cream = [Color(rgb: 0xFFFFFF), Color(rgb: 0xFFF7E8), Color(rgb: 0xFFF1DC)]
    /// The plain letter on small tiles: one solid deeper red, about 6.3:1 on the cream. The chunky face's gradient
    /// starts at about 4.7:1, and with no outline behind it the accessibility audit measured the small letter
    /// under 4.5:1 (it reads a gradient-filled glyph's edges poorly).
    static let plainFace = [Color(rgb: 0xA82A08)]

    var body: some View {
        let side = size * min(scale, 1.4)
        let shape = RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
        // Small tiles (the writing header, the countdown) show a plain red letter: at that size the outline
        // would sit right against the face and pull its contrast under 4.5:1. Their letter is a solid deeper red.
        let chunky = side >= 100
        ChunkyText(text: Text(verbatim: letter).font(.system(size: side * 0.6, weight: .black, design: .rounded)),
                   outline: chunky ? max(1.5, side * 0.025) : 0, depth: chunky ? max(1.5, side * 0.035) : 0,
                   face: chunky ? ChunkyText.defaultFace : Self.plainFace)
            .contentTransition(.identity)
            .offset(y: -side * 0.02)
            .frame(width: side, height: side)
            .background {
                ZStack {
                    shape.fill(Theme.ink).offset(y: max(3, side * 0.05))
                    shape.fill(LinearGradient(colors: Self.cream, startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(Theme.ink, lineWidth: max(2, side * 0.03))
                }
            }
            .padding(.bottom, max(3, side * 0.05))
    }
}

/// A letter tile at the centre of a sunburst: the big reveal.
struct SunburstTile: View {
    let letter: String
    var size: CGFloat = 168

    @Environment(\.reduceMotion) private var reduceMotion
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.4)
        LetterTile(letter: letter, size: size)
            .background {
                Sunburst(isAnimated: !reduceMotion, rays: 22, period: 24)
                    .frame(width: side * 2.1, height: side * 2.1)
            }
            .padding(.vertical, side * 0.3)
    }
}

#Preview("Letter reveal") {
    LetterRevealView(round: Round(number: 2, letter: "B", participants: []), gameID: UUID())
        .background(Theme.background)
}

#Preview("Letter reveal – reduce motion") {
    LetterRevealView(round: Round(number: 2, letter: "M", participants: []), gameID: UUID())
        .background(Theme.background)
        .environment(\.reduceMotion, true)
}
