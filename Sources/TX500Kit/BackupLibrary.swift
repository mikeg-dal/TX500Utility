import Foundation

/// A folder of settings backups (`.set` files). Every backup, whether read from the radio or
/// imported from elsewhere (e.g. Lab599 TRXSettings), lives here as a 1024-byte file.
///
/// The source is encoded in the file name, so no extra metadata file is needed:
/// `TX500-settings-<timestamp>.set` (from the radio) and `TX500-imported-<name>@<timestamp>.set`.
public struct BackupLibrary: Sendable {
    public enum Source: String, Sendable {
        case radio, imported
    }

    public struct Entry: Identifiable, Hashable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let date: Date
        public let source: Source

        /// The original file name for imported backups (without prefix and timestamp).
        public var displayName: String? {
            guard source == .imported else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            let body = stem.dropFirst(BackupLibrary.importedPrefix.count)
            guard let cut = body.range(of: BackupLibrary.nameSeparator, options: .backwards) else { return String(body) }
            return String(body[..<cut.lowerBound])
        }
    }

    public enum LibraryError: Error, LocalizedError {
        case notInLibrary(URL)

        public var errorDescription: String? {
            switch self {
            case let .notInLibrary(url): "\(url.lastPathComponent) is not in the backup library"
            }
        }
    }

    public let directory: URL

    static let radioPrefix = "TX500-settings-"
    static let importedPrefix = "TX500-imported-"
    /// Separates an imported file's original name from the timestamp (never produced by name cleaning).
    static let nameSeparator = "@"
    /// Suffix separator for de-duplicating names saved within the same second.
    static let duplicateSeparator = "-"
    private static let timestampFormat = "yyyyMMdd-HHmmss"
    /// Characters allowed from an imported file's original name.
    private static let allowedNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Newest first.
    public func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { $0.pathExtension == TX500Protocol.Settings.fileExtension }
            .map { url in
                let date = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let source: Source = url.lastPathComponent.hasPrefix(Self.importedPrefix) ? .imported : .radio
                return Entry(url: url, date: date, source: source)
            }
            .sorted { $0.date > $1.date }
    }

    /// Saves a backup read from the radio.
    @discardableResult
    public func save(_ backup: SettingsBackup, date: Date = Date()) throws -> URL {
        let url = uniqueURL(named: Self.radioPrefix + Self.timestamp(date))
        try backup.fileData.write(to: url, options: .atomic)
        return url
    }

    /// Copies an external `.set` file into the library after validating it.
    @discardableResult
    public func importFile(from source: URL, date: Date = Date()) throws -> URL {
        let backup = try SettingsBackup(fileData: Data(contentsOf: source))
        let original = source.deletingPathExtension().lastPathComponent
        let cleaned = String(original.unicodeScalars.map { Self.allowedNameCharacters.contains($0) ? Character($0) : "_" })
        let url = uniqueURL(named: Self.importedPrefix + cleaned + Self.nameSeparator + Self.timestamp(date))
        try backup.fileData.write(to: url, options: .atomic)
        return url
    }

    /// Writes a copy of `entry` to `destination` (overwriting it).
    public func export(_ entry: Entry, to destination: URL) throws {
        let data = try Data(contentsOf: entry.url)
        try data.write(to: destination, options: .atomic)
    }

    /// Moves the backup to the Trash so it can be recovered.
    public func delete(_ entry: Entry) throws {
        guard entry.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw LibraryError.notInLibrary(entry.url)
        }
        try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
    }

    public func load(_ entry: Entry) throws -> SettingsBackup {
        try SettingsBackup(fileData: Data(contentsOf: entry.url))
    }

    // MARK: Private

    private func uniqueURL(named stem: String) -> URL {
        let ext = TX500Protocol.Settings.fileExtension
        var url = directory.appendingPathComponent(stem).appendingPathExtension(ext)
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            url = directory.appendingPathComponent(stem + Self.duplicateSeparator + String(counter)).appendingPathExtension(ext)
        }
        return url
    }

    private static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = timestampFormat
        return f.string(from: date)
    }
}
