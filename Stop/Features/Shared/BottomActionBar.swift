import SwiftUI

/// A full-width call to action pinned above the home indicator, on the cream page under a thin rule. Its text stops growing at
/// the second accessibility size, so the pinned bar never crowds out the screen it sits on.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            content
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.outline.opacity(0.25))
                .frame(height: 1.5)
                .accessibilityHidden(true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // A container, so the identifier doesn't replace its buttons' own (the accessibility audit test uses it).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottomActionBar")
    }
}
