import SwiftUI

/// Inline, dismissible error message shown at the top of a feature view.
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.warning)
            Text(message)
                .font(Theme.Typography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.warning.opacity(Theme.Opacity.tint),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}
