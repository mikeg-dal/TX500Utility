import SwiftUI

/// Colored dot + short label, used for connection state and RX/TX.
@MainActor
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: Theme.Metrics.statusDotSize, height: Theme.Metrics.statusDotSize)
            Text(text.uppercased())
                .font(Theme.Typography.badge)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(color.opacity(Theme.Opacity.tint), in: Capsule())
    }
}
