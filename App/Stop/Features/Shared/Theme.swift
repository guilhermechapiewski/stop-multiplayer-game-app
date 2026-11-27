import SwiftUI

/// The app's visual language: bold rounded type, one warm "stop" accent (the `AccentColor` asset, tuned for
/// light, dark and increased contrast), generous spacing. Everything scales with Dynamic Type.
enum Theme {
    static let accent = Color.accentColor
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 20
        static let card: CGFloat = 24
    }

    enum Typography {
        static let display = Font.system(.largeTitle, design: .rounded, weight: .black)
        static let title = Font.system(.title, design: .rounded, weight: .bold)
        static let headline = Font.system(.title3, design: .rounded, weight: .bold)
        static let body = Font.system(.body, design: .rounded)
        static let caption = Font.system(.subheadline, design: .rounded, weight: .medium)
    }
}

// MARK: Buttons

/// The main call to action: full width, filled with the accent.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.reduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, Theme.Spacing.m)
            .background(isEnabled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.fill),
                        in: .rect(cornerRadius: Theme.Radius.control))
            .pressEffect(configuration.isPressed, reduceMotion: reduceMotion)
    }
}

/// Secondary actions: full width, tinted with the accent.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.reduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, Theme.Spacing.m)
            .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: Theme.Radius.control))
            .pressEffect(configuration.isPressed, reduceMotion: reduceMotion)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

private extension View {
    func pressEffect(_ pressed: Bool, reduceMotion: Bool) -> some View {
        self
            .opacity(pressed ? 0.85 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.2), value: pressed)
    }
}

// MARK: Stop sign

/// A regular octagon, flat sides on top and bottom, like a stop sign.
struct Octagon: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // The apothem (centre to a flat side) is half the shorter side.
        let radius = (min(rect.width, rect.height) / 2 - insetAmount) / cos(.pi / 8)
        var path = Path()
        for index in 0..<8 {
            let angle = Double.pi / 8 + Double(index) * .pi / 4
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Octagon { Octagon(insetAmount: insetAmount + amount) }
}

/// The app's mark, drawn like the app icon: a white-rimmed stop sign reading "STOP!". Decorative, so hidden
/// from VoiceOver.
struct StopSign: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            Octagon().fill(.white)
            Octagon()
                .inset(by: size * 0.045)
                .fill(Theme.accent.gradient)
            Text(verbatim: "STOP!")
                .font(.system(size: size * 0.24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, size * 0.12)
        }
        .frame(width: size, height: size)
        // A crisp contact shadow outlines the white rim on light backgrounds; the glow gives depth.
        .shadow(color: .black.opacity(0.18), radius: size * 0.015, y: size * 0.008)
        .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
    }
}

// MARK: Players

/// A player's initial in a tinted circle. Decorative: the name is always shown beside it.
struct PlayerInitial: View {
    let name: String
    var dimmed = false
    var size: CGFloat = 40
    /// Practice bots ("Robo Ana") show their own name's initial, so they don't all read "R".
    var isBot = false
    /// The local player: never mistaken for a bot, even if their name starts with "Robo ".
    var isYou = false

    @ScaledMetric private var scale: CGFloat = 1
    /// In practice, views that don't know who's a bot (scoring, results) still get the bots' own initials.
    @Environment(\.isPracticeGame) private var isPractice

    /// Bots are flagged by the caller, or recognised by name — only other players, and only in practice.
    nonisolated static func showsBotInitial(name: String, isBot: Bool, isPractice: Bool, isYou: Bool) -> Bool {
        isBot || (isPractice && !isYou && PracticeSetupModel.isBotName(name))
    }

    nonisolated static func initial(for name: String, isBot: Bool) -> String {
        let words = name.split(separator: " ")
        let source = isBot && words.count > 1 ? words[1] : Substring(name)
        return source.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Text(verbatim: Self.initial(for: name, isBot: Self.showsBotInitial(name: name, isBot: isBot, isPractice: isPractice, isYou: isYou)))
            .font(.system(size: size * scale * 0.45, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size * scale, height: size * scale)
            .background(dimmed ? AnyShapeStyle(Color(.systemGray)) : AnyShapeStyle(Theme.accent.gradient), in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: Layout

extension View {
    /// Scrollable screen content that is vertically centred when it fits and scrolls when Dynamic Type
    /// makes it taller than the screen.
    func centeredScrolling() -> some View {
        modifier(CenteredScrolling())
    }
}

private struct CenteredScrolling: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, minHeight: height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
    }
}
