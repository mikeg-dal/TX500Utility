import SwiftUI

@MainActor
struct RootView: View {
    @Environment(RadioLoader.self) private var loader
    @State private var selection: AppSection? = .radio

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                branding
            }
            .navigationSplitViewColumnWidth(min: Theme.Metrics.sidebarMinWidth, ideal: Theme.Metrics.sidebarMinWidth)
        } detail: {
            VStack(spacing: 0) {
                ConnectionBar()
                Divider()
                detail(for: selection ?? .radio)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .overlay {
            if loader.isOverlayVisible {
                LoadingOverlayView()
            }
        }
        .animation(Theme.Splash.fadeAnimation, value: loader.isOverlayVisible)
    }

    /// Logo and version at the foot of the sidebar. Reuses the splash artwork, which is the same
    /// wordmark without the dark square behind it, so it sits properly on the sidebar material.
    private var branding: some View {
        VStack(spacing: Theme.Spacing.xs) {
            SplashImage.logo
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Theme.Metrics.brandingWidth)
                .accessibilityLabel(AppStrings.appName)
            Text("v\(AppStrings.version)")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .help("\(AppStrings.appName) \(AppStrings.version) — \(AppStrings.author)")
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .radio: RadioView()
        case .memories: MemoriesView()
        case .settings: SettingsBackupView()
        case .clock: ClockView()
        case .firmware: FirmwareView()
        case .diagnostics: DiagnosticsView()
        }
    }
}
