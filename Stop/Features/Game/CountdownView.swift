import Foundation
import StopCore
import SwiftUI

/// 3, 2, 1 under the round's letter. Each number is a host tick, so the count pauses while the host is away.
struct CountdownView: View {
    let round: Round
    let gameID: UUID
    let secondsRemaining: Int
    /// Host only: draws another letter.
    var onReroll: (() -> Void)?

    @Environment(\.reduceMotion) private var reduceMotion
    /// The first number waits a moment so it doesn't cut off "Letter B" (spoken as the letter lands, or as this
    /// view appears).
    @State private var announcedANumber = false

    static let firstAnnouncementDelay: Duration = .milliseconds(800)

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                LetterTile(letter: round.letter, size: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Round \(round.number)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text("Letter \(round.letter)")
                        .font(Theme.Typography.title)
                }
            }
            .accessibilityElement(children: .combine)

            Text(secondsRemaining, format: .number)
                .font(.system(size: 200, weight: .black, design: .rounded))
                .minimumScaleFactor(0.5)
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .id(secondsRemaining)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .scale(scale: 1.8).combined(with: .opacity),
                                          removal: .scale(scale: 0.4).combined(with: .opacity)))
                .accessibilityLabel(Text("\(secondsRemaining) seconds"))
                .accessibilityIdentifier("countdownNumber")

            Text("Get ready to write!")
                .font(Theme.Typography.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let onReroll { NewLetterButton(action: onReroll) }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.35),
                   value: secondsRemaining)
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
        .onAppear { LetterAnnouncement.announce(round, gameID: gameID) }
        .onChange(of: secondsRemaining, initial: true) { _, seconds in
            GameFeedback.play(.countdownTick(seconds))
        }
        .task(id: secondsRemaining) {
            if !announcedANumber {
                do {
                    try await Task.sleep(for: Self.firstAnnouncementDelay)
                } catch {
                    // The next tick came first: skip this number and announce that one at once.
                    announcedANumber = true
                    return
                }
            }
            announcedANumber = true
            AccessibilityNotification.Announcement(secondsRemaining.formatted()).post()
        }
    }
}

#Preview("Countdown") {
    @Previewable @State var seconds = 3
    CountdownView(round: Round(number: 1, letter: "B", participants: []), gameID: UUID(), secondsRemaining: seconds)
        .background(Theme.background)
        .task {
            while true {
                try? await Task.sleep(for: .seconds(1))
                seconds = seconds > 1 ? seconds - 1 : 3
            }
        }
}
