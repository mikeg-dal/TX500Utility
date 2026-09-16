import Foundation

/// Identifies a settings viewer window: the backup to show and an optional backup to compare against.
/// Backups are always file-based (radio reads are saved first), so windows can be restored and reopened.
struct SettingsViewerRequest: Codable, Hashable {
    var fileURL: URL
    var compareURL: URL?

    static let windowID = "settings-viewer"
}
