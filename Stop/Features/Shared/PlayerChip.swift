import StopCore
import SwiftUI

/// A player's name and initial on a game tile. Away players are greyed out with "reconnecting…".
struct PlayerChip: View {
    let name: String
    let presence: Presence
    var isHost = false
    var isYou = false
    /// A practice bot: its initial comes from its own name ("Robo Ana" → A).
    var isBot = false

    private var isAway: Bool { presence == .away }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PlayerInitial(name: name, dimmed: isAway, size: 30, isBot: isBot, isYou: isYou)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: name)
                        .font(Theme.Typography.body.weight(.bold))
                        .foregroundStyle(isAway ? Theme.secondaryText : Theme.text)
                    if isHost {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.crown)
                            .accessibilityHidden(true)
                    }
                }
                if isAway {
                    Text("reconnecting…")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                } else if isYou {
                    Text("you")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.leading, Theme.Spacing.s)
        .padding(.trailing, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        // A game tile: cream, the local player's tinted and outlined in the accent; away players flat and grey.
        .piece(RoundedRectangle(cornerRadius: Theme.Radius.tile + 2, style: .continuous),
               fill: isAway ? Theme.sunken : isYou ? Theme.accentTint : Theme.surface,
               outline: isAway ? Theme.outline.opacity(0.4) : isYou ? Theme.accent : Theme.outline,
               depth: isAway ? 0 : 3)
        .padding(.bottom, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(accessibilityDetails)
        .accessibilityIdentifier("playerChip")
    }

    private var accessibilityDetails: Text {
        Text(verbatim: AccessibilityText.playerDetails(presence: presence, isHost: isHost, isYou: isYou, isBot: isBot))
    }
}

#Preview("Player chips") {
    FlowLayout(spacing: Theme.Spacing.s) {
        PlayerChip(name: "Gui", presence: .present, isHost: true, isYou: true)
        PlayerChip(name: "Ana", presence: .present)
        PlayerChip(name: "Ana 2", presence: .away)
        PlayerChip(name: "Robo Ben", presence: .present, isBot: true)
    }
    .padding()
}
