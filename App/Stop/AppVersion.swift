import Foundation

/// The version shown in About, e.g. "1.0 (1)" (`MARKETING_VERSION (CURRENT_PROJECT_VERSION)`).
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        return display(short: info?["CFBundleShortVersionString"] as? String ?? "1.0",
                       build: info?["CFBundleVersion"] as? String ?? "1")
    }

    static func display(short: String, build: String) -> String { "\(short) (\(build))" }
}
