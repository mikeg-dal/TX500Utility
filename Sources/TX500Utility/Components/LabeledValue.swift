import SwiftUI

/// Small caption above a prominent value, e.g. "POWER / 10 W". Shows an em dash when the value is unknown.
struct LabeledValue: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label.uppercased())
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(value ?? Placeholder.unknown)
                .font(Theme.Typography.value)
                .foregroundStyle(Theme.Palette.primaryText)
        }
    }
}
