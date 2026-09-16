import SwiftUI

/// Compact on/off indicator for a radio function (VOX, MON, NB…). Hidden state is shown dimmed, not removed,
/// so the badge row keeps a stable layout.
@MainActor
struct FunctionBadge: View {
    let title: String
    let isOn: Bool?
    var detail: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title)
            if let detail {
                Text(detail).fontWeight(.regular)
            }
        }
        .font(Theme.Typography.badge)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(isOn == true ? Theme.Palette.badgeOn : Theme.Palette.badgeOff)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background((isOn == true ? Theme.Palette.badgeOn : Theme.Palette.badgeOff).opacity(Theme.Opacity.tint),
                    in: Capsule())
        .opacity(isOn == nil ? Theme.Opacity.badgeOff : 1)
        .help(isOn == nil ? "\(title): not reported by the radio" : "\(title): \(isOn! ? "on" : "off")")
    }
}
