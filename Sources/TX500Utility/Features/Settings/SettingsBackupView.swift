import SwiftUI
import TX500Kit

/// Settings Backups: one library of `.set` backups with the same actions on every row.
struct SettingsBackupView: View {
    @Environment(RadioConnection.self) private var connection
    @Environment(BackupStore.self) private var store
    @Environment(RadioLoader.self) private var loader
    @Environment(\.openWindow) private var openWindow
    @State private var model = SettingsBackupModel()
    @State private var pendingRestore: BackupStore.Entry?
    @State private var pendingDelete: BackupStore.Entry?

    var body: some View {
        SectionPage {
            if let message = model.errorMessage {
                ErrorBanner(message: message) { model.errorMessage = nil }
            }
            headerCard
            listCard
        }
        .confirmationDialog("Restore settings to the radio?", isPresented: isPresented($pendingRestore), presenting: pendingRestore) { entry in
            Button("Back Up Current, Then Restore", role: .destructive) {
                Task { await model.restore(entry, connection: connection, loader: loader, store: store) }
            }
        } message: { entry in
            Text("All of the radio's menu settings will be replaced with the backup from \(entry.date.formatted(date: .abbreviated, time: .shortened)). A fresh backup of the current settings is taken first.")
        }
        .confirmationDialog("Delete this backup?", isPresented: isPresented($pendingDelete), presenting: pendingDelete) { entry in
            Button("Move to Trash", role: .destructive) { model.delete(entry, store: store) }
        } message: { entry in
            Text("The backup from \(entry.date.formatted(date: .abbreviated, time: .shortened)) is moved to the Trash. You can recover it from there.")
        }
    }

    // MARK: Header

    private var headerCard: some View {
        Card("Settings Backups") {
            Text("A backup is a complete copy of the radio's menu settings, saved on this Mac as a .set file (compatible with Lab599 TRXSettings).")
                .foregroundStyle(Theme.Palette.secondaryText)
            Text("It does not include memory channels or the clock — those live elsewhere in the radio. Export a .mem file for memories, and set the clock from the Clock page.")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text("Restoring takes a fresh backup of the radio first, then writes only the bytes that differ and reads each one back to check it.")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
            HStack(spacing: Theme.Spacing.md) {
                Button("Back Up Radio Now") {
                    Task { await model.backUpNow(connection: connection, loader: loader, store: store) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!connection.isConnected || model.isBusy || loader.isLoading)
                .help("Reads all settings from the radio (about 12 seconds). Nothing on the radio is changed.")

                Button("Import .set File…") { model.importFile(store: store) }
                    .disabled(model.isBusy)
                    .help("Add a backup made elsewhere, e.g. with TRXSettings on Windows")

                if !connection.isConnected {
                    Text("Connect to back up or restore.")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            if let progress = model.progress {
                ProgressPanel(progress: progress)
            }
            if loader.isLoading {
                Text("Reading the radio's settings in the background…")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondaryText)
            } else if let note = loader.backupNote, model.statusMessage == nil {
                Label(note, systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.Palette.success)
            }
            if let status = model.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.Palette.success)
            }
        }
    }

    // MARK: List

    private var listCard: some View {
        Card("Your Backups") {
            if store.entries.isEmpty {
                Text("No backups yet. Press Back Up Radio Now.")
                    .foregroundStyle(Theme.Palette.secondaryText)
            } else {
                ForEach(store.entries) { entry in
                    BackupRow(
                        entry: entry,
                        otherEntries: store.entries.filter { $0 != entry },
                        matchesRadio: model.matchesRadio(entry, radio: loader.settings, store: store),
                        canRestore: connection.isConnected && !model.isBusy && !loader.isLoading,
                        onView: { openViewer(entry.url) },
                        onCompare: { other in openViewer(entry.url, compare: other.url) },
                        onExport: { model.export(entry, store: store) },
                        onRestore: { pendingRestore = entry },
                        onDelete: { pendingDelete = entry }
                    )
                    if entry != store.entries.last { Divider() }
                }
            }
        }
    }

    // MARK: Helpers

    private func openViewer(_ url: URL, compare: URL? = nil) {
        openWindow(id: SettingsViewerRequest.windowID, value: SettingsViewerRequest(fileURL: url, compareURL: compare))
    }

    private func isPresented(_ item: Binding<BackupStore.Entry?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}
