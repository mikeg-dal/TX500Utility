import Foundation
import Observation
import TX500Kit

/// Observable wrapper around `BackupLibrary` for the app. Backups live in
/// ~/Library/Application Support/TX500 Utility/Backups. Used by Settings Backups, the Settings
/// Viewer (compare list) and Firmware (latest backup).
@MainActor
@Observable
final class BackupStore {
    typealias Entry = BackupLibrary.Entry

    private(set) var entries: [Entry] = []
    private let library: BackupLibrary?

    private static let folderName = "Backups"

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent(AppStrings.appName).appendingPathComponent(Self.folderName)
        library = try? BackupLibrary(directory: directory)
        reload()
    }

    var latest: Entry? { entries.first }

    /// Which bytes ever differ between the backups on this Mac (used to mark inert bytes in the viewer).
    var comparison: BackupComparison {
        BackupComparison(backups: entries.compactMap { try? load($0) })
    }

    @discardableResult
    func save(_ backup: SettingsBackup) throws -> URL {
        let url = try requireLibrary().save(backup)
        reload()
        return url
    }

    @discardableResult
    func importFile(from url: URL) throws -> URL {
        let imported = try requireLibrary().importFile(from: url)
        reload()
        return imported
    }

    func export(_ entry: Entry, to destination: URL) throws {
        try requireLibrary().export(entry, to: destination)
    }

    func delete(_ entry: Entry) throws {
        try requireLibrary().delete(entry)
        reload()
    }

    func load(_ entry: Entry) throws -> SettingsBackup {
        try requireLibrary().load(entry)
    }

    func reload() {
        entries = library?.entries() ?? []
    }

    private func requireLibrary() throws -> BackupLibrary {
        guard let library else { throw CocoaError(.fileWriteNoPermission) }
        return library
    }
}
