import StopCore
import StopSession
import SwiftUI

/// Scoring, one category at a time: everyone's answers and current scores, read-only, and each player scores
/// their own (10 / 5 / 0). The host can score for players who are away. Once everyone has scored, picks stay
/// editable until the host taps Next category (See results after the last).
struct ScoringView: View {
    let client: any GameClient
    let state: GameState
    let round: Round

    @Environment(\.reduceMotion) private var reduceMotion
    /// My pick, shown at once while the host confirms it.
    @State private var pendingPick: Int?

    private var me: PlayerID { client.localPlayerID }
    private var presentation: ScoringPresentation { ScoringPresentation(state: state, viewer: me) }
    private var isCompleted: Bool { presentation.isCompleted }
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: presentation.rows.map(\.score))
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
                    AnswerRow(row: row, isMe: row.playerID == me)
                    if presentation.canHostScore.contains(row.playerID) {
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
                .strokeBorder(Theme.accent.opacity(0.6), lineWidth: isCompleted ? 1.5 : 0)
        }
    }

    // MARK: Picker and Next

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
                // Stays enabled once the category is complete: a wrong pick can be fixed until the host moves on.
                ScorePicker(selection: pendingPick ?? presentation.myScore,
                            options: presentation.myAnswerIsBlank ? [0] : [10, 5, 0]) { points in
                    pendingPick = points
                    GameFeedback.play(.scorePicked)
                    client.send(.setScore(round: round.number, category: presentation.categoryIndex,
                                          points: points, player: me))
                }
                if presentation.myAnswerIsBlank {
                    Text("Blank answers score 0.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                } else if presentation.isReadAloud, presentation.myScore == nil {
                    Text("Read your answer out loud, then score it.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("readAloudHint")
                }
            }
            if !isCompleted {
                waitingLine(presentation)
            } else if !presentation.showsAdvanceButton {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Waiting for \(presentation.hostName) to continue…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(minHeight: 32)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("waitingForHost")
            }
            if presentation.showsAdvanceButton { hostButtons(presentation) }
        }
    }

    /// Host only: Previous beside Next (from the second category on), stacked when they don't fit side by side
    /// (large text, long labels).
    @ViewBuilder private func hostButtons(_ presentation: ScoringPresentation) -> some View {
        if presentation.showsPreviousButton {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    previousButton(presentation)
                    nextButton(presentation)
                }
                VStack(spacing: Theme.Spacing.s) {
                    nextButton(presentation)
                    previousButton(presentation)
                }
            }
        } else {
            nextButton(presentation)
        }
    }

    /// Host only: takes everyone back to the category before, to review or correct its scores.
    private func previousButton(_ presentation: ScoringPresentation) -> some View {
        Button {
            client.send(.previousCategory(round: round.number, category: presentation.categoryIndex))
        } label: {
            Label("Previous category", systemImage: "arrow.backward")
        }
        .buttonStyle(.secondary)
        .accessibilityHint(Text("Takes everyone back to the category before."))
        .accessibilityIdentifier("previousCategoryButton")
    }

    /// Host only: moves everyone on once the category is complete.
    private func nextButton(_ presentation: ScoringPresentation) -> some View {
        Button {
            client.send(.nextCategory(round: round.number, category: presentation.categoryIndex))
        } label: {
            if presentation.isLastCategory {
                Label("See results", systemImage: "trophy")
            } else {
                Label("Next category", systemImage: "arrow.forward")
            }
        }
        .buttonStyle(.primary)
        .disabled(!presentation.canAdvance)
        .accessibilityHint(presentation.canAdvance ? Text(verbatim: "") : Text("Available once everyone has scored."))
        .accessibilityIdentifier("nextCategoryButton")
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

/// One player's answer and their current score (10 / 5 / 0), or "…" until they pick one.
private struct AnswerRow: View {
    let row: ScoringPresentation.Row
    let isMe: Bool

    private var isBlank: Bool { row.isBlank }
    private var isAway: Bool { row.presence != .present }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.reduceMotion) private var reduceMotion

    /// "Ana (you) · away": one string, so it wraps as a sentence at large text sizes.
    private var nameLine: String {
        var parts = [row.name]
        if isMe { parts.append(String(localized: "(you)")) }
        if row.presence == .away { parts.append(String(localized: "· away")) }
        if row.presence == .left || row.presence == .removed { parts.append(String(localized: "· left")) }
        return parts.joined(separator: " ")
    }

    var body: some View {
        // At accessibility sizes the (decorative) initial gives its room to the name and answer.
        HStack(spacing: Theme.Spacing.m) {
            if !dynamicTypeSize.isAccessibilitySize {
                PlayerInitial(name: row.name, dimmed: isAway, size: 36, isYou: isMe)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: nameLine)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                if row.isHidden {
                    // Read aloud: shown once this player scores it.
                    Text(verbatim: "…")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Text(verbatim: row.answer)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(isBlank ? .secondary : .primary)
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .scale(scale: 0.85, anchor: .leading)
                                                      .combined(with: .opacity),
                                                  removal: .opacity))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Spacing.s)
            status
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.name))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(row.isHidden ? "answerRowHidden" : "answerRow")
    }

    private var status: some View {
        ScoreBadge(score: row.score)
    }

    private var accessibilityValue: Text {
        if row.isHidden { return Text("Answer hidden until scored") }
        let answer = isBlank ? Text("Blank") : Text(verbatim: row.answer)
        guard let score = row.score else { return Text("\(answer), not scored yet") }
        return Text("\(answer), \(score) points")
    }
}

/// A player's points for the category: filled for 10 and 5, muted for 0, "…" while not scored yet. A minimum
/// width keeps the answers lined up whatever the score.
private struct ScoreBadge: View {
    let score: Int?

    @ScaledMetric(relativeTo: .title3) private var width: CGFloat = 48
    @ScaledMetric(relativeTo: .title3) private var height: CGFloat = 34

    var body: some View {
        if let score {
            Text(score, format: .number)
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(score > 0 ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, Theme.Spacing.s)
                .frame(minWidth: width, minHeight: height)
                .background(fill(score), in: .capsule)
                .contentTransition(.numericText(value: Double(score)))
                .transition(.scale.combined(with: .opacity))
        } else {
            Text(verbatim: "…")
                .font(Theme.Typography.headline)
                .foregroundStyle(.secondary)
                .frame(minWidth: width, minHeight: height)
                .overlay { Capsule().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
                .accessibilityLabel(Text("Not scored yet"))
        }
    }

    private func fill(_ score: Int) -> AnyShapeStyle {
        switch score {
        case 10: AnyShapeStyle(Theme.accent)
        case 5: AnyShapeStyle(Theme.accent.opacity(0.7))
        default: AnyShapeStyle(.fill.tertiary)
        }
    }
}

/// Three large segments: 10, 5, 0 (only 0 for a blank answer).
private struct ScorePicker: View {
    let selection: Int?
    let options: [Int]
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
                .accessibilityLabel(Text(verbatim: AccessibilityText.score(points)))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("score-\(points)")
            }
        }
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

#Preview("Scoring – host, completed") {
    let client = PreviewData.client(isHost: true, phase: .scoring(categoryIndex: 5, completed: true))
    var state = client.state!
    let ids = state.players.map(\.id)
    state.rounds[0].answers = Dictionary(uniqueKeysWithValues: ids.map { ($0, Array(repeating: "Bread", count: 6)) })
    state.rounds[0].answers[ids[1]]?[5] = "Bagel"
    state.rounds[0].answers[ids[3]]?[5] = ""
    state.rounds[0].scores = Dictionary(uniqueKeysWithValues: ids.map { ($0, [10, 10, 10, 10, 10, 5]) })
    state.rounds[0].scores[ids[1]]?[5] = 10
    state.rounds[0].scores[ids[3]]?[5] = 0
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
