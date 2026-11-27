import Foundation

/// The app's name as shown in the UI. A placeholder until the owner picks the App Store name; change it here
/// (and `INFOPLIST_KEY_CFBundleDisplayName`, `InfoPlist.xcstrings`).
enum AppInfo {
    static let name = "Stop!"

    /// The App Store ID, from App Store Connect.
    static let appStoreID = "6840139205"
    /// The app's App Store page (Tell a friend's QR code and share link). Region-neutral: the App Store opens the
    /// visitor's own storefront.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
}

/// The version shown in About, e.g. "1.0 (1)" (`MARKETING_VERSION (CURRENT_PROJECT_VERSION)`).
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        return display(short: info?["CFBundleShortVersionString"] as? String ?? "1.0",
                       build: info?["CFBundleVersion"] as? String ?? "1")
    }

    static func display(short: String, build: String) -> String { "\(short) (\(build))" }
}
