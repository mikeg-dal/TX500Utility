import SwiftUI

/// Standard scrolling page layout for a feature section.
@MainActor
struct SectionPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                content
            }
            .padding(Theme.Spacing.xl)
        }
    }
}
