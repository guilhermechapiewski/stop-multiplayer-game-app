import SwiftUI

/// The project's public pages.
enum AboutLinks {
    static let site = "https://guilhermechapiewski.github.io/stop-multiplayer-game-app"
    static let sourceCode = URL(string: "https://github.com/guilhermechapiewski/stop-multiplayer-game-app")!
    static let reportProblem = URL(string: "https://github.com/guilhermechapiewski/stop-multiplayer-game-app/issues/new")!

    /// App Store Review Guideline 5.1.1(i): the privacy policy must be reachable inside the app too.
    /// Portuguese UIs get the Portuguese page.
    static func privacyPolicy(languageCode: String) -> URL {
        let path = languageCode.hasPrefix("pt") ? "/pt/privacidade/" : "/privacy/"
        return URL(string: site + path)!
    }

    /// The privacy policy in the language the app's UI is showing.
    static var privacyPolicy: URL {
        privacyPolicy(languageCode: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: Theme.Spacing.m) {
                    StopSign(size: 96)
                    VStack(spacing: Theme.Spacing.xs) {
                        Text(verbatim: AppInfo.name)
                            .font(Theme.Typography.title)
                            .accessibilityAddTraits(.isHeader)
                        Text("Version \(AppVersion.display)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("appVersion")
                    }
                    Text("Free and open source. No ads, no accounts, no tracking.")
                        .font(Theme.Typography.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.l)
                .listRowBackground(Color.clear)
            }

            Section {
                Link(destination: AboutLinks.privacyPolicy) {
                    Label("Privacy policy", systemImage: "lock.shield.fill")
                }
                .accessibilityIdentifier("privacyPolicyLink")
                Link(destination: AboutLinks.sourceCode) {
                    Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .accessibilityHint("Opens the project on GitHub.")
                .accessibilityIdentifier("sourceCodeLink")
                Link(destination: AboutLinks.reportProblem) {
                    Label("Report a problem", systemImage: "ladybug.fill")
                }
                .accessibilityHint("Opens a new issue on GitHub.")
                .accessibilityIdentifier("reportProblemLink")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AboutView() }
}
