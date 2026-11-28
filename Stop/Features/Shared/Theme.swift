import SwiftUI
import UIKit

/// The app's visual language, drawn from the app icon: warm cream paper (a deep warm brown at night), chunky
/// rounded type, dark-brown outlines and a red-orange "stop" accent with yellow and teal from the icon.
/// Buttons, cards and tiles are "game pieces": outlined, standing on a hard bottom edge they sink into when
/// pressed. Every text color meets WCAG AA (4.5:1) on the surfaces it is used on; everything scales with
/// Dynamic Type.
enum Theme {
    // MARK: Colors

    /// Text, icons and outlines in the accent (red-orange): #C8360F on cream, brighter at night.
    static let accent = dynamic(light: 0xC8360F, dark: 0xFF7F57, lightHigh: 0xA82A08, darkHigh: 0xFF9B7A)
    /// The accent as a fill behind white text (primary buttons, the 10-point badge).
    static let accentFill = dynamic(light: 0xC8360F, dark: 0xD23C14, lightHigh: 0xA82A08, darkHigh: 0xB8300C)
    /// The darker edge a filled accent piece stands on.
    static let accentEdge = dynamic(light: 0x7A1C04, dark: 0x5E1504)
    /// A soft accent wash: the local player's rows and chips.
    static let accentTint = dynamic(light: 0xFFECE1, dark: 0x45231A)
    /// White on `accentFill`.
    static let onAccent = Color.white

    /// Yellow from the icon's sparkle: fills behind `ink` text (labels, the 5-point badge, highlights).
    static let yellow = dynamic(light: 0xFFC93C, dark: 0xF2B92E)
    /// Teal: "done" and "back" states. `teal` for text and icons, `tealFill` behind `ink` text.
    static let teal = dynamic(light: 0x08706A, dark: 0x5BD1C4, lightHigh: 0x075E58, darkHigh: 0x86E2D7)
    static let tealFill = dynamic(light: 0x3CC2B3, dark: 0x2FA797)

    /// The page: warm cream, or a deep warm brown-black at night.
    static let background = dynamic(light: 0xFFF4E2, dark: 0x1C1410)
    /// Cards, fields and list rows.
    static let surface = dynamic(light: 0xFFFDF8, dark: 0x2B201A)
    /// Read-only fields and empty slots, a step down from `surface`.
    static let sunken = dynamic(light: 0xF8ECDA, dark: 0x231A15)
    /// Text on every surface above.
    static let text = dynamic(light: 0x2B140D, dark: 0xFFF3E3)
    /// Secondary text (at least 5.7:1 on every surface above, the tints included).
    static let secondaryText = dynamic(light: 0x6B4E42, dark: 0xD2BCAC, lightHigh: 0x4A3128, darkHigh: 0xEBDACB)
    /// Dark-brown outlines of the playful pieces (a warm mid-brown at night, where they sit on dark surfaces):
    /// at least 3:1 against the page in every appearance, so fields and cards show where they are.
    static let outline = dynamic(light: 0x3A1A12, dark: 0x7C5E4D, lightHigh: 0x2A0F08, darkHigh: 0x8A6A58)
    /// The hard edge and drop shadow under pieces.
    static let edge = dynamic(light: 0x3A1A12, dark: 0x080403)
    /// Dark-brown text on the yellow and teal fills, in both appearances.
    static let ink = Color(rgb: 0x3A1A12)
    /// Disabled buttons: a flat fill and a muted (still legible) label.
    static let disabledFill = dynamic(light: 0xEADCC8, dark: 0x352923)
    static let disabledText = dynamic(light: 0x5A463C, dark: 0xBBA697)
    /// Hairlines between rows inside a card.
    static let divider = dynamic(light: 0xEAD8C0, dark: 0x3D2F27)

    /// The leader's crown: a deep gold in light mode (plain yellow is under 2:1 on the light rows), the icon's
    /// yellow at night.
    static let crown = dynamic(light: 0x8A5900, dark: 0xF2B92E)

    /// The sunburst's two ray colors (behind the letter, the STOP! stamp and the winner).
    static let sunburstRay = dynamic(light: 0xFFB347, dark: 0xB8410F)
    static let sunburstGap = dynamic(light: 0xFFD98A, dark: 0x7A2A0C)

    /// Player tiles: each player gets one of these fills, with a letter color that passes 4.5:1 on it.
    static let tileColors: [(fill: Color, letter: Color)] = [
        (accentFill, .white),
        (Color(rgb: 0xFFC93C), ink),
        (Color(rgb: 0x3CC2B3), ink),
        (Color(rgb: 0xFF9A52), ink),
        (Color(rgb: 0x7C5CD6), .white),
    ]

    /// A color for light and dark appearances (and, optionally, Increase Contrast).
    static func dynamic(light: UInt32, dark: UInt32, lightHigh: UInt32? = nil, darkHigh: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            let value = traits.userInterfaceStyle == .dark ? (high ? darkHigh ?? dark : dark)
                                                           : (high ? lightHigh ?? light : light)
            return UIColor(rgb: value)
        })
    }

    // MARK: Metrics

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 18
        static let card: CGFloat = 22
        static let tile: CGFloat = 12
    }

    /// Outlines and the hard edge under pieces.
    enum Stroke {
        static let outline: CGFloat = 2
        static let button: CGFloat = 2.5
        /// How far a piece stands on its edge (and sinks when pressed).
        static let depth: CGFloat = 4
    }

    enum Typography {
        static let display = Font.system(.largeTitle, design: .rounded, weight: .black)
        static let title = Font.system(.title, design: .rounded, weight: .heavy)
        static let headline = Font.system(.title3, design: .rounded, weight: .bold)
        static let body = Font.system(.body, design: .rounded)
        static let caption = Font.system(.subheadline, design: .rounded, weight: .semibold)
        /// Bubble labels and buttons' small print.
        static let label = Font.system(.subheadline, design: .rounded, weight: .heavy)
    }

    /// UIKit chrome (navigation bar titles) in the app's type, set once at launch.
    @MainActor static func applyAppearance() {
        func rounded(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            // The default size, like the system's own titles: a navigation bar title doesn't grow with Dynamic
            // Type (it would crowd out the bar's buttons).
            let size = UIFont.preferredFont(forTextStyle: style,
                                            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
                .pointSize
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            return font
        }
        let text = UIColor(rgb: 0x2B140D, dark: 0xFFF3E3)
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: rounded(.headline, .heavy), .foregroundColor: text]
        bar.largeTitleTextAttributes = [.font: rounded(.largeTitle, .black), .foregroundColor: text]
    }
}

extension Color {
    /// An sRGB color from 0xRRGGBB.
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// Light and dark variants.
    convenience init(rgb light: UInt32, dark: UInt32) {
        self.init { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) }
    }
}

// MARK: Pieces

/// The look of a game piece: a fill with an outline, standing on a hard edge `depth` below it. Draws only the
/// background; the content's frame is the piece's face (the edge hangs below it).
struct PieceBackground<S: InsettableShape>: View {
    let shape: S
    var fill: Color = Theme.surface
    var outline: Color = Theme.outline
    var edge: Color = Theme.edge
    var lineWidth: CGFloat = Theme.Stroke.outline
    var depth: CGFloat = Theme.Stroke.depth

    var body: some View {
        ZStack {
            if depth > 0 {
                shape.fill(edge).offset(y: depth)
            }
            shape.fill(fill)
            shape.strokeBorder(outline, lineWidth: lineWidth)
        }
    }
}

extension View {
    /// A card: the surface, outlined, on a hard edge.
    func pieceCard(fill: Color = Theme.surface, cornerRadius: CGFloat = Theme.Radius.card,
                   depth: CGFloat = Theme.Stroke.depth) -> some View {
        background(PieceBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                                   fill: fill, depth: depth))
    }

    /// A text field's box: cream and outlined, the outline turning red-orange (and thicker) while focused;
    /// read-only fields sit flat on the sunken color.
    func pieceField(isFocused: Bool, isReadOnly: Bool = false, cornerRadius: CGFloat = 14) -> some View {
        background(PieceBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                                   fill: isReadOnly ? Theme.sunken : Theme.surface,
                                   outline: isFocused ? Theme.accent : Theme.outline.opacity(isReadOnly ? 0.35 : 1),
                                   lineWidth: isFocused ? 3 : Theme.Stroke.outline, depth: isReadOnly ? 0 : 3))
    }

    /// A piece of any shape (tiles, chips, badges).
    func piece<S: InsettableShape>(_ shape: S, fill: Color, outline: Color = Theme.outline, edge: Color = Theme.edge,
                                   lineWidth: CGFloat = Theme.Stroke.outline,
                                   depth: CGFloat = Theme.Stroke.depth) -> some View {
        background(PieceBackground(shape: shape, fill: fill, outline: outline, edge: edge, lineWidth: lineWidth,
                                   depth: depth))
    }
}

// MARK: Buttons

/// A game-piece button: outlined, on an edge it sinks into while pressed (no movement with Reduce Motion
/// beyond the sink itself, which isn't animated then).
struct PieceButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let foreground: Color
    let edge: Color
    let minHeight: CGFloat
    let isEnabled: Bool
    let reduceMotion: Bool
    var font: Font = Theme.Typography.headline
    var cornerRadius: CGFloat = Theme.Radius.control
    /// Stretches to the width offered (the full-width buttons); off, it is as wide as its label.
    var fillsWidth = true

    private var depth: CGFloat { isEnabled ? Theme.Stroke.depth : 0 }

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .font(font)
            .foregroundStyle(isEnabled ? foreground : Theme.disabledText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight)
            .background {
                shape.fill(isEnabled ? fill : Theme.disabledFill)
                shape.strokeBorder(isEnabled ? Theme.outline : Theme.outline.opacity(0.35),
                                   lineWidth: Theme.Stroke.button)
            }
            .contentShape(shape)
            .offset(y: pressed ? depth : 0)
            .background {
                if depth > 0 {
                    shape.fill(edge)
                        .overlay { shape.strokeBorder(Theme.outline, lineWidth: Theme.Stroke.button) }
                        .offset(y: depth)
                }
            }
            .padding(.bottom, Theme.Stroke.depth)
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: pressed)
    }
}

/// The main call to action: full width, red-orange, white text.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.reduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        PieceButtonBody(configuration: configuration, fill: Theme.accentFill, foreground: Theme.onAccent,
                        edge: Theme.accentEdge, minHeight: minHeight, isEnabled: isEnabled,
                        reduceMotion: reduceMotion)
    }
}

/// Secondary actions: full width, cream with red-orange text.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.reduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        PieceButtonBody(configuration: configuration, fill: Theme.surface, foreground: Theme.accent,
                        edge: Theme.edge, minHeight: minHeight, isEnabled: isEnabled, reduceMotion: reduceMotion)
    }
}

/// Small text actions (New letter, Back to scoring, End game): bold accent text with a 44 pt target that dims
/// while pressed.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == LinkButtonStyle {
    static var link: LinkButtonStyle { LinkButtonStyle() }
}

// MARK: Display type

/// Big chunky letters like the icon's "STOP!": a red-orange face with a dark-brown outline and a dark
/// extrusion below. `text` stays the only accessibility element (labels and identifiers applied outside land
/// on it): the outline is drawn in a `Canvas`, which VoiceOver and UI tests never see. Pass a `Text` that
/// already has its font.
struct ChunkyText: View {
    let text: Text
    /// The outline's thickness, in points.
    var outline: CGFloat = 4
    /// How far the extrusion drops below the face.
    var depth: CGFloat = 6
    /// Top to bottom; every stop is at least 4.5:1 on the cream letter tile.
    var face: [Color] = [Color(rgb: 0xC8360F), Color(rgb: 0xB8300C), Color(rgb: 0xA82A08)]
    var ink: Color = Theme.ink
    var minimumScaleFactor: CGFloat = 1

    /// Eight directions around the face, for the outline.
    private static let directions: [CGSize] = (0..<8).map { index in
        let angle = Double(index) / 8 * 2 * .pi
        return CGSize(width: cos(angle), height: sin(angle))
    }

    var body: some View {
        text
            .minimumScaleFactor(minimumScaleFactor)
            .foregroundStyle(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
            .background {
                if outline > 0 || depth > 0 { outlineLayer }
            }
    }

    /// The outline and extrusion: copies of the text in ink, drawn around and below the face.
    private var outlineLayer: some View {
        // Grown on every side so the outline and extrusion aren't clipped; the centre stays the face's.
        let margin = outline + depth
        return Canvas { context, size in
            let copy = context.resolve(text.foregroundStyle(ink))
            let natural = copy.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
            // Follows the face when `minimumScaleFactor` shrinks it.
            let scale = min(1, (size.width - 2 * margin) / max(1, natural.width),
                            (size.height - 2 * margin) / max(1, natural.height))
            for direction in Self.directions {
                for drop in [depth, 0] {
                    var layer = context
                    layer.translateBy(x: size.width / 2 + direction.width * outline,
                                      y: size.height / 2 + direction.height * outline + drop)
                    layer.scaleBy(x: scale, y: scale)
                    layer.draw(copy, at: .zero, anchor: .center)
                }
            }
        }
        .padding(-margin)
        .accessibilityHidden(true)
    }
}

// MARK: Labels

/// A comic speech bubble: a rounded body with a small tail, at the bottom leading corner (labels) or centred
/// on top (a caption under what it talks about). The rect includes the tail: pad the content by `tailSize`
/// on that side.
struct SpeechBubble: InsettableShape {
    var cornerRadius: CGFloat = 12
    var tailSize: CGFloat = 8
    var tailOnTop = false
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + (tailOnTop ? tailSize : 0), width: rect.width,
                          height: rect.height - tailSize)
            .insetBy(dx: inset, dy: inset)
        let radius = min(cornerRadius, body.height / 2)
        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        var tail = Path()
        if tailOnTop {
            tail.move(to: CGPoint(x: body.midX - tailSize, y: body.minY + 1))
            tail.addLine(to: CGPoint(x: body.midX - tailSize * 0.2, y: body.minY - tailSize + inset))
            tail.addLine(to: CGPoint(x: body.midX + tailSize, y: body.minY + 1))
        } else {
            let start = body.minX + radius + 2
            tail.move(to: CGPoint(x: start, y: body.maxY - 1))
            tail.addLine(to: CGPoint(x: start - tailSize * 0.4, y: body.maxY + tailSize - inset))
            tail.addLine(to: CGPoint(x: start + tailSize * 1.4, y: body.maxY - 1))
        }
        tail.closeSubpath()
        path.addPath(tail)
        return path.normalized(eoFill: false)
    }

    func inset(by amount: CGFloat) -> SpeechBubble {
        var copy = self
        copy.inset += amount
        return copy
    }
}

/// A section's title on a yellow speech bubble ("Players (4)"), dark-brown text, a header for VoiceOver.
struct BubbleLabel: View {
    let title: Text
    var systemImage: String?
    var fill: Color = Theme.yellow

    @ScaledMetric(relativeTo: .subheadline) private var tail: CGFloat = 7

    init(_ title: LocalizedStringKey, systemImage: String? = nil, fill: Color = Theme.yellow) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.fill = fill
    }

    init(_ title: Text, systemImage: String? = nil, fill: Color = Theme.yellow) {
        self.title = title
        self.systemImage = systemImage
        self.fill = fill
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            title
        }
        .font(Theme.Typography.label)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.Spacing.s + 4)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .padding(.bottom, tail)
        .background {
            let shape = SpeechBubble(cornerRadius: 12, tailSize: tail)
            shape.fill(Theme.edge).offset(y: 2.5)
            shape.fill(fill)
            shape.strokeBorder(Theme.ink, lineWidth: Theme.Stroke.outline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A `List` section's header: chunky, warm brown, in sentence case.
struct ListSectionHeader: View {
    let title: Text

    init(_ title: LocalizedStringKey) { self.title = Text(title) }
    init(_ title: Text) { self.title = title }

    var body: some View {
        title
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.secondaryText)
            .textCase(nil)
    }
}

/// A list row's icon on a small outlined tile, like a settings icon cut from the game's pieces.
struct TileIconLabelStyle: LabelStyle {
    var fill: Color = Theme.accentFill
    var symbolColor: Color = .white

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        // Grows with the text, but stops at 44 pt so the title keeps the room at accessibility sizes.
        let side = min(self.side, 44)
        HStack(spacing: Theme.Spacing.m) {
            configuration.icon
                .font(.system(size: side * 0.5, weight: .bold))
                .foregroundStyle(symbolColor)
                .frame(width: side, height: side)
                .piece(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous), fill: fill,
                       outline: Theme.ink, lineWidth: 1.5, depth: 2)
                .accessibilityHidden(true)
            configuration.title
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
    }
}

extension LabelStyle where Self == TileIconLabelStyle {
    static func tile(_ fill: Color, symbol: Color = .white) -> TileIconLabelStyle {
        TileIconLabelStyle(fill: fill, symbolColor: symbol)
    }
}

// MARK: Players

/// A player's initial on a small game tile, in a color of their own. Decorative: the name is always shown
/// beside it.
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
        #if DEBUG
        isBot || (isPractice && !isYou && PracticeSetupModel.isBotName(name))
        #else
        isBot  // No practice games in Release builds.
        #endif
    }

    nonisolated static func initial(for name: String, isBot: Bool) -> String {
        let words = name.split(separator: " ")
        let source = isBot && words.count > 1 ? words[1] : Substring(name)
        return source.first.map { String($0).uppercased() } ?? "?"
    }

    /// A stable color slot for `name` (the same on every phone and every launch).
    nonisolated static func colorIndex(for name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return sum % count
    }

    var body: some View {
        // Grows with the text, up to 1.6×, so names keep the room at the accessibility sizes.
        let side = size * min(scale, 1.6)
        let colors = Theme.tileColors[Self.colorIndex(for: name, count: Theme.tileColors.count)]
        let shape = RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
        Text(verbatim: Self.initial(for: name, isBot: Self.showsBotInitial(name: name, isBot: isBot, isPractice: isPractice, isYou: isYou)))
            .font(.system(size: side * 0.5, weight: .black, design: .rounded))
            .foregroundStyle(dimmed ? Theme.disabledText : colors.letter)
            .frame(width: side, height: side)
            .piece(shape, fill: dimmed ? Theme.disabledFill : colors.fill,
                   outline: dimmed ? Theme.outline.opacity(0.4) : Theme.ink,
                   lineWidth: max(1.5, side * 0.05), depth: dimmed ? 0 : max(2, side * 0.07))
            .accessibilityHidden(true)
            .accessibilityIdentifier("playerInitial")
    }
}

// MARK: Layout

extension View {
    /// Scrollable screen content that is vertically centred when it fits and scrolls when Dynamic Type
    /// makes it taller than the screen.
    func centeredScrolling() -> some View {
        modifier(CenteredScrolling())
    }

    /// A `List` or `Form` on the app's cream page, with surface rows.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
            .listRowBackground(Theme.surface)
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
