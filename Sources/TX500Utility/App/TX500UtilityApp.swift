import AppKit
import SwiftUI

/// Closing the window quits the app, and quitting releases the serial port.
///
/// macOS keeps an app running with no windows by default, which for a single-window utility just
/// leaves the port held open so nothing else can use it until the user notices and quits properly.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the app's state exists; called on the way out.
    var releasePort: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        releasePort?()
    }
}

@main
struct TX500UtilityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var connection: RadioConnection
    @State private var backups: BackupStore
    @State private var loader: RadioLoader

    init() {
        let connection = RadioConnection()
        let backups = BackupStore()
        _connection = State(initialValue: connection)
        _backups = State(initialValue: backups)
        _loader = State(initialValue: RadioLoader(connection: connection, backups: backups))
        // Launched via `swift run` there is no bundle; make the app a regular foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup(AppStrings.appName) {
            RootView()
                .environment(connection)
                .environment(backups)
                .environment(loader)
                .frame(minWidth: Theme.Metrics.contentMinWidth, minHeight: Theme.Metrics.contentMinHeight)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    appDelegate.releasePort = { connection.disconnect() }
                }
        }

        WindowGroup("Settings Viewer", id: SettingsViewerRequest.windowID, for: SettingsViewerRequest.self) { $request in
            if let request {
                SettingsViewerView(request: request)
                    .environment(backups)
                    .environment(connection)
                    .environment(loader)
                }
        }

        .commands {
            // Apple's standard panel, filled in from the bundle, rather than a custom window.
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppStrings.appName)") { showAbout() }
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

private func showAbout() {
    let centred = NSMutableParagraphStyle()
    centred.alignment = .center
    let credits = NSMutableAttributedString(
        string: [AppStrings.author, AppStrings.summary, AppStrings.disclaimer].joined(separator: "\n"),
        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                     .foregroundColor: NSColor.secondaryLabelColor,
                     .paragraphStyle: centred])
    NSApplication.shared.orderFrontStandardAboutPanel(options: [
        .applicationName: AppStrings.appName,
        .applicationVersion: AppStrings.version,
        .credits: credits,
    ])
    NSApplication.shared.activate(ignoringOtherApps: true)
}

enum AppStrings {
    static let appName = "TX500 Utility"
    static let author = "by Mike (KF5O)"
    static let summary = "A utility for the Lab599 Discovery TX-500."
    /// Shown in About. This app is independent — nothing about it should read as Lab599's own.
    static let disclaimer = "Not affiliated with Lab599."

    /// Used when there is no bundle to read from (`swift run`). `Scripts/build-app.sh` refuses to
    /// build if this disagrees with the VERSION file, so the two cannot drift apart unnoticed.
    static let fallbackVersion = "0.9.0"

    /// The version this build was made from.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }
}
