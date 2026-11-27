import StopCore
import StopSession
import SwiftUI

/// Scoring, one category at a time: everyone's answers read-only, and each player scores their own
/// (10 / 5 / 0). The host can score for players who are away. A completed category is highlighted for a beat
/// before the host's tick moves on.
struct ScoringView: View {
    let client: any GameClient
    let state: GameState
    let round: Round

    @Environment(\.reduceMotion) private var reduceMotion
    /// My pick, shown at once while the host confirms it.
    @State private var pendingPick: Int?

    private var me: PlayerID { client.localPlayerID }
    private var presentation: ScoringPresentation { ScoringPresentation(state: state, viewer: me) }
    private var isCompleted: Bool {
        if case .scoring(_, true) = state.phase { true } else { false }
    }
    private var isParticipant: Bool { round.participants.contains(me) }

    var body: some View {
        let presentation = presentation
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header(presentation)
                answersCard(presentation)
                    .id(presentation.categoryIndex)
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                              removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.l)
        }
        .safeAreaInset(edge: .bottom) { picker(presentation) }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4),
                   value: presentation.categoryIndex)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: isCompleted)
        .onChange(of: presentation.categoryIndex) { pendingPick = nil }
        .onChange(of: presentation.myScore) { _, score in
            if score == pendingPick { pendingPick = nil }
        }
        .onChange(of: isCompleted) { _, completed in
            if completed { GameFeedback.play(.categoryCompleted) }
        }
    }

    // MARK: Header

    private func header(_ presentation: ScoringPresentation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Round \(round.number) · Letter \(round.letter)")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: presentation.categoryName)
                    .font(Theme.Typography.display)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: Theme.Spacing.s)
                Text("\(presentation.categoryIndex + 1) of \(presentation.total)")
                    .font(Theme.Typography.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("scoringCategory-\(presentation.categoryIndex)")
            ProgressView(value: Double(presentation.categoryIndex + (isCompleted ? 1 : 0)),
                         total: Double(max(1, presentation.total)))
                .tint(Theme.accent)
                .accessibilityHidden(true)
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: Answers

    private func answersCard(_ presentation: ScoringPresentation) -> some View {
        VStack(spacing: 0) {
            ForEach(presentation.rows) { row in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    AnswerRow(row: row, isMe: row.playerID == me, isCompleted: isCompleted)
                    if presentation.canHostScore.contains(row.playerID) && !isCompleted {
                        HostScoreControl(row: row) { points in
                            client.send(.setScore(round: round.number, category: presentation.categoryIndex,
                                                  points: points, player: row.playerID))
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s + 2)
                .background(row.playerID == me ? Theme.accent.opacity(0.1) : .clear)
                if row.id != presentation.rows.last?.id { Divider().padding(.leading, 64) }
            }
        }
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.accent, lineWidth: isCompleted ? 2.5 : 0)
        }
    }

    // MARK: Picker

    @ViewBuilder private func picker(_ presentation: ScoringPresentation) -> some View {
        BottomActionBar {
            if !isParticipant {
                Text("You’ll play from the next round.")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            } else {
                Text(isCompleted ? "Everyone has scored!" : "Score your answer")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(isCompleted ? Theme.accent : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(isCompleted ? "categoryCompleted" : "scorePickerTitle")
                ScorePicker(selection: pendingPick ?? presentation.myScore,
                            options: presentation.myAnswerIsBlank ? [0] : [10, 5, 0],
                            isEnabled: !isCompleted) { points in
                    pendingPick = points
                    GameFeedback.play(.scorePicked)
                    client.send(.setScore(round: round.number, category: presentation.categoryIndex,
                                          points: points, player: me))
                }
                if presentation.myAnswerIsBlank {
                    Text("Blank answers score 0.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                if !isCompleted { waitingLine(presentation) }
            }
        }
    }

    /// "Waiting for Ana and Bia" while others still have to score.
    @ViewBuilder private func waitingLine(_ presentation: ScoringPresentation) -> some View {
        let waiting = presentation.rows.filter { $0.score == nil && $0.presence.isActive && $0.playerID != me }
        if !waiting.isEmpty {
            Text("Waiting for \(waiting.map(\.name).formatted(.list(type: .and)))")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

/// One player's answer, with a checkmark once they've scored (their points once the category completes).
private struct AnswerRow: View {
    let row: ScoringPresentation.Row
    let isMe: Bool
    let isCompleted: Bool

    private var isBlank: Bool { row.isBlank }
    private var isAway: Bool { row.presence != .present }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            PlayerInitial(name: row.name, dimmed: isAway, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: row.name)
                    if isMe { Text("(you)") }
                    if row.presence == .away { Text("· away") }
                    if row.presence == .left || row.presence == .removed { Text("· left") }
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                Text(verbatim: row.answer)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(isBlank ? .secondary : .primary)
            }
            Spacer(minLength: Theme.Spacing.s)
            status
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.name))
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder private var status: some View {
        if isCompleted, let score = row.score {
            Text(score, format: .number)
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(score > 0 ? .white : .secondary)
                .frame(minWidth: 44, minHeight: 32)
                .background(score > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.fill.tertiary), in: .capsule)
                .transition(.scale.combined(with: .opacity))
        } else if row.score != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .transition(.scale.combined(with: .opacity))
        } else {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }

    private var accessibilityValue: Text {
        let answer = isBlank ? Text("Blank") : Text(verbatim: row.answer)
        guard let score = row.score else { return Text("\(answer), not scored yet") }
        return isCompleted ? Text("\(answer), \(score) points") : Text("\(answer), scored")
    }
}

/// Three large segments: 10, 5, 0 (only 0 for a blank answer).
private struct ScorePicker: View {
    let selection: Int?
    let options: [Int]
    let isEnabled: Bool
    let onPick: (Int) -> Void

    @ScaledMetric(relativeTo: .title) private var height: CGFloat = 64

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(options, id: \.self) { points in
                let selected = selection == points
                Button { onPick(points) } label: {
                    Text(points, format: .number)
                        .font(Theme.Typography.title.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: height)
                        .foregroundStyle(selected ? .white : Theme.accent)
                        .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14)),
                                    in: .rect(cornerRadius: Theme.Radius.control))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(Text("\(points) points"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("score-\(points)")
            }
        }
        .opacity(isEnabled ? 1 : 0.6)
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

/// Host-only: score for a player who is away (or left) so the category can finish.
private struct HostScoreControl: View {
    let row: ScoringPresentation.Row
    let onPick: (Int) -> Void

    private var isBlank: Bool { row.isBlank }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(row.presence == .away ? "Away — score for \(row.name)" : "Left — score for \(row.name)")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(isBlank ? [0] : [10, 5, 0], id: \.self) { points in
                Button { onPick(points) } label: {
                    Text(points, format: .number)
                        .font(Theme.Typography.caption.monospacedDigit().weight(.bold))
                        .frame(minWidth: 40, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
                .accessibilityLabel(Text("Give \(row.name) \(points) points"))
                .accessibilityIdentifier("hostScore-\(points)")
            }
        }
        .padding(.leading, 52)
    }
}

#Preview("Scoring – host, away player") {
    let client = PreviewData.client(isHost: true, phase: .scoring(categoryIndex: 1, completed: false))
    var state = client.state!
    let ids = state.players.map(\.id)
    state.rounds[0].answers = Dictionary(uniqueKeysWithValues: ids.map {
        ($0, ["Bruno", "Bear", "Brazil", "Banana", "Blue", "Bread"])
    })
    state.rounds[0].answers[ids[2]]?[1] = ""
    state.rounds[0].scores = Dictionary(uniqueKeysWithValues: ids.map { ($0, [10, nil, nil, nil, nil, nil]) })
    state.rounds[0].scores[ids[1]]?[1] = 5
    state.rounds[0].scores[ids[2]]?[1] = 0
    client.state = state
    return ScoringView(client: client, state: state, round: state.rounds[0])
        .background(Theme.background)
}

#Preview("Scoring – completed") {
    let client = PreviewData.client(isHost: false, phase: .scoring(categoryIndex: 0, completed: true))
    var state = client.state!
    let ids = state.players.map(\.id)
    state.rounds[0].answers = Dictionary(uniqueKeysWithValues: ids.map { ($0, Array(repeating: "Bear", count: 6)) })
    state.rounds[0].scores = Dictionary(uniqueKeysWithValues: ids.map { ($0, [10, nil, nil, nil, nil, nil]) })
    state.rounds[0].scores[ids[1]]?[0] = 5
    return ScoringView(client: client, state: state, round: state.rounds[0])
        .background(Theme.background)
}
