import SwiftUI
import TX500Kit

@MainActor
struct FirmwareView: View {
    @Environment(RadioConnection.self) private var connection
    @Environment(RadioLoader.self) private var loader
    @Environment(BackupStore.self) private var store
    @State private var model = FirmwareModel()
    @State private var confirmUpdate = false

    var body: some View {
        SectionPage {
            disconnectCard
            fileCard
            backupCard
            loaderCard
            resultCard
        }
        // The radio cannot answer CAT once it is in loader mode, so the port is released the moment
        // this page opens. Doing it here means the user never sees a connected app talking to a
        // silent radio while they follow the steps below.
        .onAppear { model.prepare(connection: connection) }
    }

    // MARK: 1. Disconnect

    private var disconnectCard: some View {
        Card("1 · CAT Disconnected") {
            Label(model.didDisconnect ? "The app has disconnected from the radio."
                                      : "The app is not connected to the radio.",
                  systemImage: "checkmark.circle")
                .foregroundStyle(Theme.Palette.success)
            Text("A radio in loader mode does not answer CAT commands, so the app releases the serial port before you start. It stays released until the update finishes.")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(portNote)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }

    // MARK: 1. File

    private var fileCard: some View {
        Card("2 · Firmware File") {
            HStack(spacing: Theme.Spacing.md) {
                Button("Choose .fw File…") { model.chooseFile() }
                    .disabled(model.isWorking)
                if let error = model.imageError {
                    Label(error, systemImage: "xmark.octagon").foregroundStyle(Theme.Palette.danger)
                }
            }
            if let image = model.image {
                HStack(spacing: Theme.Spacing.xl) {
                    LabeledValue(label: "File", value: image.fileName)
                    LabeledValue(label: "Version", value: image.versionFromFileName)
                    LabeledValue(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(image.data.count), countStyle: .file))
                }
                Text("SHA-256 \(image.sha256)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: 2. Backup

    private var backupCard: some View {
        Card("3 · Back Up Settings (recommended)") {
            if let latest = store.latest {
                LabeledValue(label: "Latest backup", value: latest.date.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text("No settings backup yet.").foregroundStyle(Theme.Palette.warning)
            }
            HStack(spacing: Theme.Spacing.md) {
                Button("Back Up Radio Now") {
                    Task { await model.backUpNow(connection: connection, loader: loader, store: store) }
                }
                .disabled(model.isBackingUp || model.isWorking || model.portPath == nil)
                if model.isBackingUp {
                    ProgressView().controlSize(.small)
                    Text("Reading the radio's settings…").foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            switch model.backupMessage {
            case let .success(message):
                Label(message, systemImage: "checkmark.circle").foregroundStyle(Theme.Palette.success)
            case let .failure(message):
                Label(message, systemImage: "xmark.octagon").foregroundStyle(Theme.Palette.danger)
            case nil:
                EmptyView()
            }
            Text("Do this before the next step: a radio already in loader mode cannot be backed up. This reconnects briefly, reads the settings, then releases the port again — you do not need to leave this page.")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }

    // MARK: 3. Loader

    private var loaderCard: some View {
        Card("4 · Put the Radio in Loader Mode") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("1. Turn the TX-500 off. Keep the CAT cable connected.")
                Text("2. Hold the third button from the left in the row of buttons above the screen, and press POWER.")
                Text("3. The screen shows “The loader is waiting…”.")
            }
            Toggle("The radio shows “The loader is waiting…”", isOn: $model.loaderModeConfirmed)
                .disabled(model.isWorking)

            Button("Update Firmware…") { confirmUpdate = true }
                .disabled(!canRun)
            Label("Once the update starts, the radio's current firmware is erased. If the update is interrupted, the radio stays in loader mode. Just run the update again.",
                  systemImage: "info.circle")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .confirmationDialog("Update the radio firmware?", isPresented: $confirmUpdate) {
            Button("Update to \(model.image?.versionFromFileName ?? "selected firmware")", role: .destructive) {
                Task { await model.update(connection: connection) }
            }
        } message: {
            Text("Do not disconnect the cable or power off the radio or Mac until the update finishes (about a minute).")
        }
    }

    private var canRun: Bool {
        model.image != nil && model.loaderModeConfirmed && !model.isWorking && model.portPath != nil
    }

    private var portNote: String {
        let port = model.portPath.map { ($0 as NSString).lastPathComponent } ?? "no port selected"
        return "The update will use \(port) at \(TX500Protocol.Bootloader.baudRate) baud."
    }

    // MARK: 4. Result

    @ViewBuilder
    private var resultCard: some View {
        switch model.stage {
        case .idle:
            EmptyView()
        case let .updating(phase):
            Card("Updating") {
                switch phase {
                case .handshaking: ProgressView("Sending header…")
                case let .transferring(sent, total):
                    ProgressView(value: model.transferFraction ?? 0) {
                        Text("Transferring firmware")
                    } currentValueLabel: {
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(sent), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))")
                            .font(Theme.Typography.monoSmall)
                    }
                case .verifying: ProgressView("Waiting for the radio to confirm…")
                case .finished: ProgressView("Finishing…")
                }
                Label("Do not disconnect or power off.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Palette.warning)
            }
        case .succeeded:
            Card("5 · Update Complete") {
                Label("The radio accepted the firmware.", systemImage: "checkmark.seal")
                    .foregroundStyle(Theme.Palette.success)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("1. Turn the radio off and on again — it starts normally, not in loader mode.")
                    Text("2. The version appears on the radio's own startup screen. The radio does not report it over CAT, so the app cannot check it for you.")
                    Text("3. Press Reconnect to resume normal control.")
                }
                HStack(spacing: Theme.Spacing.md) {
                    Button("Reconnect") { Task { await model.reconnect(loader: loader) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(connection.isConnected)
                    Button("Done") { model.reset() }
                }
                if connection.isConnected {
                    Label("Connected again.", systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.Palette.success)
                }
            }
        case let .failed(message):
            Card("Update Failed") {
                Label(message, systemImage: "xmark.octagon").foregroundStyle(Theme.Palette.danger)
                Text("Your radio is safe to retry: it will start in loader mode (“The loader is waiting…”). Check the cable, then press Update Firmware again.")
                Button("Dismiss") { model.reset() }
            }
        }
    }
}
