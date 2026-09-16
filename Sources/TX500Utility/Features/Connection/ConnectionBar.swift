import SwiftUI
import TX500Kit

/// Toolbar strip shown above every section: port picker, connect button, status.
@MainActor
struct ConnectionBar: View {
    @Environment(RadioConnection.self) private var connection
    @Environment(RadioLoader.self) private var loader

    var body: some View {
        @Bindable var connection = connection

        HStack(spacing: Theme.Spacing.md) {
            Picker("Port", selection: $connection.selectedPortPath) {
                ForEach(connection.ports) { port in
                    Text(port.displayName).tag(Optional(port.path))
                }
            }
            // Capped so the status badge keeps its full width at the minimum window size; the
            // picker takes the slack when the window is wider.
            .frame(maxWidth: Theme.Metrics.portPickerMaxWidth)
            .disabled(connection.isConnected)

            Button {
                connection.refreshPorts()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan serial ports")
            .disabled(connection.isConnected)

            // Only shown when it differs from the radio's own 9600, so that a connection which
            // cannot work has a visible cause rather than being a mystery.
            if AppPreferences.catBaudRate != TX500Protocol.CAT.baudRate {
                Text("\(AppPreferences.catBaudRate) baud")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.warning)
                    .help("Set in Preferences. The TX-500 itself uses \(TX500Protocol.CAT.baudRate) baud.")
            }

            if connection.isConnected {
                Button("Disconnect") { loader.disconnect() }
            } else {
                Button("Connect") { Task { await loader.connectAndLoad() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(connection.selectedPortPath == nil || connection.status == .connecting)
            }

            Spacer()
            if loader.isLoading && !loader.isOverlayVisible {
                Button {
                    loader.isOverlayVisible = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        ProgressView(value: loader.overallFraction)
                            .frame(width: Theme.Metrics.connectionProgressWidth)
                        Text(loader.overallFraction, format: .percent.precision(.fractionLength(0)))
                            .font(Theme.Typography.monoSmall)
                    }
                }
                .buttonStyle(.borderless)
                .help("Loading radio data. Click to show the loading screen.")
            }
            statusBadge
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch connection.status {
        case .disconnected:
            StatusBadge(text: "Disconnected", color: Theme.Palette.inactive)
        case .connecting:
            StatusBadge(text: "Connecting", color: Theme.Palette.warning)
        case let .connected(id):
            HStack(spacing: Theme.Spacing.sm) {
                Text(TX500Protocol.CAT.Identity(rawValue: id)?.label ?? id)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .help("CAT protocol selected on the radio (answer to ID;)")
                StatusBadge(text: "Connected", color: Theme.Palette.success)
            }
        case let .failed(message):
            StatusBadge(text: "Error", color: Theme.Palette.danger).help(message)
        }
    }
}
