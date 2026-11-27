import StopCore
import SwiftUI

/// A player's name in a capsule. Away players are greyed out with "reconnecting…".
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
            PlayerInitial(name: name, dimmed: isAway, size: 32, isBot: isBot, isYou: isYou)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: name)
                        .font(Theme.Typography.body.weight(.semibold))
                    if isHost {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                    }
                }
                if isAway {
                    Text("reconnecting…")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if isYou {
                    Text("you")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, Theme.Spacing.xs)
        .padding(.trailing, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .background(isAway ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Theme.accent.opacity(isYou ? 0.2 : 0.1)),
                    in: .capsule)
        .overlay {
            if isYou { Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5) }
        }
        .opacity(isAway ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(accessibilityDetails)
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
