import Foundation
import Observation
import TX500Kit

/// Actions for the Settings Backups page: back up, import, export, delete and restore.
/// Every backup is a `.set` file in the `BackupStore` library.
@MainActor
@Observable
final class SettingsBackupModel {
    private(set) var progress: OperationProgress?
    var errorMessage: String?
    var statusMessage: String?

    var isBusy: Bool { progress != nil }

    func backUpNow(connection: RadioConnection, loader: RadioLoader, store: BackupStore) async {
        guard let backup = await read(connection: connection, loader: loader, title: "Reading radio settings") else { return }
        do {
            try store.save(backup)
            statusMessage = "Backup saved \(Date().formatted(date: .abbreviated, time: .shortened))."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFile(store: BackupStore) {
        guard let url = FilePanels.openFile(extension: TX500Protocol.Settings.fileExtension,
                                            message: "Choose a TX-500 settings file (.set) to add to your backups") else { return }
        do {
            try store.importFile(from: url)
            statusMessage = "Imported \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export(_ entry: BackupStore.Entry, store: BackupStore) {
        guard let url = FilePanels.saveFile(extension: TX500Protocol.Settings.fileExtension,
                                            suggestedName: entry.url.lastPathComponent,
                                            message: "Export a copy of this backup (.set, TRXSettings compatible)") else { return }
        do {
            try store.export(entry, to: url)
            statusMessage = "Exported \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: BackupStore.Entry, store: BackupStore) {
        do {
            try store.delete(entry)
            statusMessage = "Backup moved to the Trash."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// True when `entry` is identical to the radio's settings as last read this session.
    func matchesRadio(_ entry: BackupStore.Entry, radio: SettingsBackup?, store: BackupStore) -> Bool {
        guard let radio, let backup = try? store.load(entry) else { return false }
        return backup == radio
    }

    /// Takes a fresh safety backup of the radio, then writes `entry` to the radio.
    func restore(_ entry: BackupStore.Entry, connection: RadioConnection, loader: RadioLoader, store: BackupStore) async {
        let target: SettingsBackup
        do {
            target = try store.load(entry)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard let safety = await read(connection: connection, loader: loader, title: "Backing up current settings first") else { return }
        do {
            try store.save(safety)
        } catch {
            errorMessage = "Restore cancelled: could not save the safety backup (\(error.localizedDescription))."
            return
        }

        let changes = target.differences(from: safety).count
        guard changes > 0 else {
            statusMessage = "The radio already has these settings. Nothing to restore."
            return
        }
        let title = "Writing \(changes) changed settings to radio"
        progress = OperationProgress(title: title, completed: 0, total: changes)
        await connection.perform { [weak self] cat in
            try await cat.writeSettings(target, current: safety) { done, total in
                Task { @MainActor in self?.progress = OperationProgress(title: title, completed: done, total: total) }
            }
        }
        progress = nil
        if let error = connection.lastError {
            errorMessage = error
            connection.lastError = nil
        } else {
            loader.updateSettings(target)
            statusMessage = "Settings restored. Power-cycle the radio to be sure all changes apply."
        }
    }

    private func read(connection: RadioConnection, loader: RadioLoader, title: String) async -> SettingsBackup? {
        progress = OperationProgress(title: title, completed: 0, total: TX500Protocol.Settings.byteCount)
        defer { progress = nil }
        var result: SettingsBackup?
        await connection.perform { [weak self] cat in
            result = try await cat.readSettings { done, total in
                Task { @MainActor in self?.progress = OperationProgress(title: title, completed: done, total: total) }
            }
        }
        if let error = connection.lastError {
            errorMessage = error
            connection.lastError = nil
        }
        if let result { loader.updateSettings(result) }
        return result
    }
}
