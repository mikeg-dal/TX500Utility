import SwiftUI

/// Tracks a long-running radio operation (read/write/flash) for display.
struct OperationProgress: Equatable {
    var title: String
    var completed: Int
    var total: Int

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

/// Progress bar with a title and "n of total" caption.
struct ProgressPanel: View {
    let progress: OperationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ProgressView(value: progress.fraction) {
                Text(progress.title).font(Theme.Typography.body)
            }
            Text("\(progress.completed) of \(progress.total)")
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }
}
