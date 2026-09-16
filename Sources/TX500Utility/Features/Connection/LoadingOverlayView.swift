import SwiftUI

/// Full-window loading screen shown after Connect while `RadioLoader` reads everything from the radio.
@MainActor
struct LoadingOverlayView: View {
    @Environment(RadioLoader.self) private var loader

    var body: some View {
        ZStack {
            Theme.Splash.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                WaterFillLogo(progress: loader.overallFraction)
                    .frame(maxWidth: Theme.Splash.logoWidth)

                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView(value: loader.overallFraction)
                        .tint(Theme.Splash.accent)
                        .frame(maxWidth: Theme.Splash.progressWidth)
                    Text(headline)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundStyle(Theme.Splash.text)
                    Text(loader.overallFraction, format: .percent.precision(.fractionLength(0)))
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Splash.secondaryText)
                }

                stepList

                buttons
            }
            .padding(Theme.Spacing.xxl)
        }
        .transition(.opacity)
    }

    private var headline: String {
        switch loader.phase {
        case let .loading(step, _): "Loading \(step.title.lowercased())…"
        case let .failed(step, _): "Couldn't load \(step.title.lowercased())"
        case .finished: "Ready"
        case .idle: "Connecting…"
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(loader.steps) { step in
                HStack(spacing: Theme.Spacing.sm) {
                    icon(for: loader.status(of: step))
                        .frame(width: Theme.Splash.stepIconWidth)
                    Text(step.title)
                        .foregroundStyle(loader.status(of: step) == .pending ? Theme.Splash.secondaryText : Theme.Splash.text)
                }
            }
            if case let .failed(_, message) = loader.phase {
                Text(message)
                    .foregroundStyle(Theme.Palette.danger)
                    .frame(maxWidth: Theme.Splash.progressWidth, alignment: .leading)
            }
        }
        .font(Theme.Typography.body)
    }

    @ViewBuilder
    private func icon(for status: RadioLoader.StepStatus) -> some View {
        switch status {
        case .pending: Image(systemName: "circle").foregroundStyle(Theme.Splash.secondaryText)
        case .active: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.Palette.danger)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: Theme.Spacing.md) {
            if case .failed = loader.phase {
                Button("Retry") { loader.retry() }
                    .keyboardShortcut(.defaultAction)
                Button("Close") { loader.isOverlayVisible = false }
            } else {
                Button("Continue in Background") { loader.isOverlayVisible = false }
                    .keyboardShortcut(.cancelAction)
                    .help("Keep loading while you use the app. Click the progress in the connection bar to come back here.")
            }
        }
    }
}
