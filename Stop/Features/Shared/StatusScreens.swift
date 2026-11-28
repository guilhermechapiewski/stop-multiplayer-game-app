import SwiftUI

/// What a `StatusMessageView` shows above its title.
enum StatusIcon {
    case symbol(String)
    case progress
}

/// A full-screen status: a symbol (or a spinner), a title, an optional explanation and optional actions,
/// centred and scrolling when Dynamic Type makes it tall.
struct StatusMessageView<Actions: View>: View {
    typealias Icon = StatusIcon

    let icon: Icon
    let title: Text
    var message: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                StatusBadge(icon: icon)
                title
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    message
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            actions
        }
        .padding(.horizontal, Theme.Spacing.l)
        .centeredScrolling()
    }
}

/// A status screen's symbol (or spinner) on a round game piece over a yellow comic burst. Decorative.
struct StatusBadge: View {
    let icon: StatusIcon
    var size: CGFloat = 88

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.4)
        let burst = Starburst(points: 12, innerRatio: 0.8)
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: side * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            case .progress:
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)
            }
        }
        .frame(width: side, height: side)
        .piece(Circle(), fill: Theme.surface, lineWidth: 2.5, depth: 5)
        .background {
            burst.fill(Theme.yellow)
                .overlay { burst.strokeBorder(Theme.ink, lineWidth: 2) }
                .frame(width: side * 1.45, height: side * 1.45)
        }
        .padding(side * 0.22)
        .accessibilityHidden(true)
    }
}

extension StatusMessageView where Actions == EmptyView {
    init(icon: Icon, title: Text, message: Text? = nil) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

/// Shown while an interrupted game is being resumed after a relaunch: a spinner, then (after about 2 minutes)
/// word that the host may be gone. With Local Network access off it points to Settings instead.
struct RejoiningView: View {
    let hostName: String
    var mayBeGone = false
    var networkDenied = false
    let onCancel: () -> Void

    var body: some View {
        let copy = HostAwayCopy(hostName: hostName, mayBeGone: mayBeGone, networkDenied: networkDenied,
                                rejoining: true)
        StatusMessageView(icon: copy.systemImage.map(StatusIcon.symbol) ?? .progress, title: Text(copy.title),
                          message: Text(copy.message)) {
            VStack(spacing: Theme.Spacing.s) {
                if networkDenied { OpenSettingsButton() }
                Button("Leave this game", action: onCancel)
                    .buttonStyle(.secondary)
                    .accessibilityHint("Stops reconnecting and goes back to the start screen.")
                    .accessibilityIdentifier("cancelRejoinButton")
            }
        }
        .background(Theme.background)
        .animation(.easeInOut(duration: 0.2), value: mayBeGone)
        .animation(.easeInOut(duration: 0.2), value: networkDenied)
        .onChange(of: mayBeGone) { _, gone in
            if gone { AccessibilityNotification.Announcement(String(localized: copy.title)).post() }
        }
    }
}

#Preview("Rejoining") {
    RejoiningView(hostName: "Ana") {}
}

#Preview("Rejoining – host may be gone") {
    RejoiningView(hostName: "Ana", mayBeGone: true) {}
}

#Preview("Rejoining – no local network") {
    RejoiningView(hostName: "Ana", networkDenied: true) {}
}
