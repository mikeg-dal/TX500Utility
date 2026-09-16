import Foundation

/// Compares a set of backups to see which bytes ever change on this radio.
///
/// Most of the settings table never moves (zero padding, fixed record fields), so telling "constant here"
/// apart from "meaning unknown" turns a wall of undecoded bytes into the handful worth investigating.
public struct BackupComparison: Sendable, Equatable {
    /// Offsets that hold the same value in every backup, with that value.
    public let constants: [Int: UInt8]
    /// Offsets that differ between at least two backups.
    public let varying: [Int]
    public let backupCount: Int

    public init(backups: [SettingsBackup]) {
        backupCount = backups.count
        guard let first = backups.first, backups.count > 1 else {
            constants = [:]
            varying = []
            return
        }
        var constants: [Int: UInt8] = [:]
        var varying: [Int] = []
        for offset in 0..<TX500Protocol.Settings.byteCount {
            let value = first.bytes[offset]
            if backups.allSatisfy({ $0.bytes[offset] == value }) {
                constants[offset] = value
            } else {
                varying.append(offset)
            }
        }
        self.constants = constants
        self.varying = varying
    }

    public var isUsable: Bool { backupCount > 1 }

    /// True when this offset held the same value in every backup.
    public func isConstant(_ offset: Int) -> Bool { constants[offset] != nil }

    /// A one-line description for an undecoded byte, e.g. "same in all 7 backups (0x40)".
    public func note(for offset: Int) -> String? {
        guard let value = constants[offset] else { return nil }
        return String(format: "same in all %d backups (0x%02X)", backupCount, value)
    }
}
