import SwiftUI
import Testing
import UIKit
@testable import Stop

@MainActor
struct ThemeContrastTests {
    /// WCAG relative luminance of an sRGB color.
    private static func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private static func contrast(_ first: Color, _ second: Color, traits: UITraitCollection) -> Double {
        let one = luminance(UIColor(first).resolvedColor(with: traits))
        let two = luminance(UIColor(second).resolvedColor(with: traits))
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }

    /// Field and card borders are what show where a control is (WCAG 1.4.11): at least 3:1 against the page,
    /// in both appearances, with and without Increase Contrast.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark], [UIAccessibilityContrast.normal, .high])
    func outlinesStandOutFromThePage(style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast) {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.accessibilityContrast = contrast
        }
        let ratio = Self.contrast(Theme.outline, Theme.background, traits: traits)
        #expect(ratio >= 3, "outline on the page is \(ratio):1")
    }
}
