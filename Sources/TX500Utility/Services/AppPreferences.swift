import Foundation
import TX500Kit

/// When to save a settings backup automatically after the connect-time load.
enum AutoBackupPolicy: String, CaseIterable, Identifiable {
    case never
    case whenChanged
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Never"
        case .whenChanged: "Only when settings changed"
        case .always: "Every time I connect"
        }
    }

    var detail: String {
        switch self {
        case .never: "Backups are saved only when you press Back Up Radio Now."
        case .whenChanged: "Saved when the radio differs from your newest backup, so the list doesn't fill up with duplicates."
        case .always: "A new backup on every connection, even if nothing changed."
        }
    }
}

/// UserDefaults keys and typed accessors for app preferences. Views bind with `@AppStorage(AppPreferences.Key…)`;
/// services read the typed accessors.
enum AppPreferences {
    enum Key {
        static let autoBackupPolicy = "autoBackupPolicy"
        static let showLoadingScreen = "showLoadingScreen"
        static let loadEverythingOnConnect = "loadEverythingOnConnect"
        static let catBaudRate = "catBaudRate"
    }

    /// Speed used for CAT. Defaults to the radio's 9600, and refuses anything not on the offered
    /// list so a stray stored value cannot leave the app unable to connect.
    static var catBaudRate: Int {
        TX500Protocol.CAT.supportedBaudRate(UserDefaults.standard.integer(forKey: Key.catBaudRate))
    }

    /// Off by default: connecting reads status, filters and clock only; memories and all settings are read on demand.
    static let defaultLoadEverythingOnConnect = false

    static var loadEverythingOnConnect: Bool {
        UserDefaults.standard.object(forKey: Key.loadEverythingOnConnect) as? Bool ?? defaultLoadEverythingOnConnect
    }

    static let defaultAutoBackupPolicy = AutoBackupPolicy.whenChanged
    static let defaultShowLoadingScreen = true

    static var autoBackupPolicy: AutoBackupPolicy {
        UserDefaults.standard.string(forKey: Key.autoBackupPolicy).flatMap(AutoBackupPolicy.init(rawValue:)) ?? defaultAutoBackupPolicy
    }

    static var showLoadingScreen: Bool {
        UserDefaults.standard.object(forKey: Key.showLoadingScreen) as? Bool ?? defaultShowLoadingScreen
    }
}
