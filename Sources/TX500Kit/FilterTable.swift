import Foundation

/// Filter passbands per mode and preset, read from the settings table.
public struct FilterTable: Sendable, Equatable {
    public enum Table: CaseIterable, Sendable {
        case ssbLow, ssbHigh, cw, am, fm

        /// CW widths verified on the radio 2026-09-15 (FIL2 in CW = 200 Hz). Others still inferred.
        var confidence: FieldConfidence { self == .cw ? .confirmed : .inferred }

        var label: String {
            switch self {
            case .ssbLow: "SSB low cut"
            case .ssbHigh: "SSB high cut"
            case .cw: "CW width"
            case .am: "AM width"
            case .fm: "FM width"
            }
        }

        var offsets: [Int] {
            let L = TX500Protocol.Settings.Layout.self
            let start: Int
            switch self {
            case .ssbLow: start = L.filterSSBLowStart
            case .ssbHigh: start = L.filterSSBHighStart
            case .cw: start = L.filterCWStart
            case .am: start = L.filterAMStart
            case .fm: start = L.filterFMStart
            }
            return (0..<TX500Protocol.CAT.rxFilterPresetCount).map { start + $0 * MemoryLayout<UInt16>.size }
        }
    }

    private let values: [Table: [Int]]

    public init(bytes: [UInt8]) {
        values = Dictionary(uniqueKeysWithValues: Table.allCases.map { table in
            (table, table.offsets.map { Int(bytes[$0]) | Int(bytes[$0 + 1]) << UInt8.bitWidth })
        })
    }

    /// Only the byte offsets needed to build a table (so the radio view can read ~40 bytes instead of 1024).
    public static var requiredOffsets: [Int] {
        Table.allCases.flatMap { $0.offsets.flatMap { [$0, $0 + 1] } }.sorted()
    }

    /// Passband width in Hz for `mode` and zero-based `preset`; nil if unknown for that mode.
    public func bandwidth(mode: OperatingMode, preset: Int) -> Int? {
        guard (0..<TX500Protocol.CAT.rxFilterPresetCount).contains(preset) else { return nil }
        switch mode {
        case .lsb, .usb:
            guard let low = values[.ssbLow]?[preset], let high = values[.ssbHigh]?[preset] else { return nil }
            return high - low
        case .cw, .cwr: return values[.cw]?[preset]
        case .am: return values[.am]?[preset]
        case .fm: return values[.fm]?[preset]
        case .dig: return nil
        }
    }

    /// "3.0 k", "300 Hz"
    public static func format(_ hz: Int) -> String {
        hz >= TX500Protocol.Settings.Layout.kilohertz
            ? String(format: "%.1f k", Double(hz) / Double(TX500Protocol.Settings.Layout.kilohertz))
            : "\(hz) Hz"
    }
}
