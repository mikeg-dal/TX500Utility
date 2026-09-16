import Foundation
import Observation
import TX500Kit

/// Loads a settings backup (and optional comparison) and prepares rows for the viewer.
@MainActor
@Observable
final class SettingsViewerModel {
    struct Row: Identifiable, Hashable {
        var id: Int { field.offset }
        let field: SettingsField
        let value: String
        let hex: String
        let previousValue: String?

        var changed: Bool { previousValue != nil }
        var offsetText: String { String(format: "0x%03X", field.offset) }
        var addressText: String { "XL\(field.catAddress)" }
    }

    private(set) var backup: SettingsBackup?
    private(set) var comparison: SettingsBackup?
    private(set) var fileName = ""
    private(set) var comparisonName: String?
    var errorMessage: String?
    var showUndecoded = false
    /// Hide undecoded bytes that hold the same value in every backup (padding, fixed record fields).
    var hideConstant = true
    /// Which bytes ever change across the user's backups; set by the view from `BackupStore`.
    var backupComparison: BackupComparison?
    var onlyChanged = false
    var searchText = ""
    /// Decoded field map shipped with the app.
    let fields = SettingsLayout.builtInFields

    func load(_ request: SettingsViewerRequest) {
        do {
            backup = try SettingsBackup(fileData: Data(contentsOf: request.fileURL))
            fileName = request.fileURL.lastPathComponent
            if let compareURL = request.compareURL {
                comparison = try SettingsBackup(fileData: Data(contentsOf: compareURL))
                comparisonName = compareURL.lastPathComponent
            } else {
                comparison = nil
                comparisonName = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setComparison(_ url: URL?) {
        guard let url else {
            comparison = nil
            comparisonName = nil
            onlyChanged = false
            return
        }
        do {
            comparison = try SettingsBackup(fileData: Data(contentsOf: url))
            comparisonName = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Byte offsets that differ from the comparison backup.
    var changedOffsets: Set<Int> {
        guard let backup, let comparison else { return [] }
        return Set(backup.differences(from: comparison))
    }

    var rows: [Row] {
        guard let backup else { return [] }
        let changed = changedOffsets
        // Always list changed bytes, even undecoded ones, so a diff never hides anything.
        let includeUndecoded = showUndecoded || !changed.isEmpty
        return SettingsLayout.rows(for: fields, includeUndecoded: includeUndecoded).compactMap { field in
            let isChanged = field.range.contains { changed.contains($0) }
            if field.group == SettingsViewerModel.undecodedGroup && !showUndecoded && !isChanged { return nil }
            if hideConstant, !isChanged, isConstantUndecoded(field) { return nil }
            if onlyChanged && !isChanged { return nil }
            if !searchText.isEmpty,
               !field.name.localizedCaseInsensitiveContains(searchText),
               !field.group.localizedCaseInsensitiveContains(searchText) { return nil }
            return Row(field: annotated(field),
                       value: field.formattedValue(in: backup.bytes),
                       hex: field.hex(in: backup.bytes),
                       previousValue: isChanged ? comparison.map { field.formattedValue(in: $0.bytes) } : nil)
        }
    }

    /// True for an undecoded byte that never differs between the user's backups.
    private func isConstantUndecoded(_ field: SettingsField) -> Bool {
        guard field.confidence == .unknown, let backupComparison, backupComparison.isUsable else { return false }
        return field.range.allSatisfy(backupComparison.isConstant)
    }

    /// Adds "same in all N backups" to undecoded rows so inert bytes are obvious.
    private func annotated(_ field: SettingsField) -> SettingsField {
        guard field.confidence == .unknown, let backupComparison, backupComparison.isUsable,
              let note = backupComparison.note(for: field.offset), field.length == 1 else { return field }
        var copy = field
        copy.note = note
        return copy
    }

    /// How many undecoded bytes are hidden because they never change.
    var constantUndecodedCount: Int {
        guard let backupComparison, backupComparison.isUsable else { return 0 }
        return SettingsLayout.rows(for: fields, includeUndecoded: true)
            .filter { $0.confidence == .unknown && $0.range.allSatisfy(backupComparison.isConstant) }
            .reduce(0) { $0 + $1.length }
    }

    /// CSV with one row per decoded field.
    ///
    /// The raw byte grid is deliberately *not* appended here. It has sixteen columns against this
    /// table's eight, and a file holding two differently shaped tables is not valid CSV: a
    /// spreadsheet misaligns the columns and a parser reads grid numbers into the named fields
    /// (Confidence showing "154", say). `hexGridCSV()` exports it as its own file instead.
    func csv() -> String {
        guard backup != nil else { return "" }
        var lines = ["Group,Setting,Value,Previous,Raw Hex,Offset,CAT Address,Confidence"]
        for row in rows {
            lines.append([row.field.group, row.field.name, row.value, row.previousValue ?? "", row.hex,
                          row.offsetText, row.addressText, row.field.confidence.rawValue].map(Self.csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// The raw table as a 16-column grid, one row per 16 bytes.
    func hexGridCSV() -> String {
        guard let backup else { return "" }
        let columns = SettingsViewerModel.gridColumns
        var lines = [(["Offset"] + (0..<columns).map { String(format: "+%X", $0) }).joined(separator: ",")]
        for rowStart in stride(from: 0, to: backup.bytes.count, by: columns) {
            let cells = backup.bytes[rowStart..<min(rowStart + columns, backup.bytes.count)].map { String($0) }
            lines.append(([String(format: "0x%03X", rowStart)] + cells).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static let gridColumns = 16
    static let undecodedGroup = SettingsLayout.undecodedGroup

    private static func csvEscape(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}
