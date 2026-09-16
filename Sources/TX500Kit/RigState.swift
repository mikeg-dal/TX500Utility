import Foundation

public enum OperatingMode: Int, CaseIterable, Sendable, Identifiable {
    case lsb = 1, usb = 2, cw = 3, fm = 4, am = 5, dig = 6, cwr = 7

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .lsb: "LSB"
        case .usb: "USB"
        case .cw: "CW"
        case .fm: "FM"
        case .am: "AM"
        case .dig: "DIG"
        case .cwr: "CWR"
        }
    }
}

/// Decoded `IF;` response (Kenwood TS-480/TS-2000 layout).
public struct InformationFrame: Equatable, Sendable {
    private typealias L = TX500Protocol.CAT.InformationFrame

    public var frequencyHz: Int
    public var ritOffsetHz: Int
    public var ritOn: Bool
    public var xitOn: Bool
    public var memoryChannel: Int
    public var transmitting: Bool
    public var mode: OperatingMode?
    public var vfo: Int
    public var scanning: Bool
    public var split: Bool

    public init?(response: String) {
        guard let body = CATResponse.body(of: response, command: "IF"), body.count == L.bodyLength else { return nil }
        let c = Array(body)
        func field(_ r: Range<Int>) -> String { String(c[r]).trimmingCharacters(in: .whitespaces) }
        func flag(_ i: Int) -> Bool { c[i] == "1" }
        guard let freq = Int(field(L.frequency)) else { return nil }
        frequencyHz = freq
        ritOffsetHz = Int(field(L.ritOffset)) ?? 0
        ritOn = flag(L.ritOn)
        xitOn = flag(L.xitOn)
        memoryChannel = Int(field(L.memoryChannel)) ?? 0
        transmitting = flag(L.transmitting)
        mode = Int(String(c[L.mode])).flatMap(OperatingMode.init(rawValue:))
        vfo = Int(String(c[L.vfo])) ?? 0
        scanning = flag(L.scan)
        split = flag(L.split)
    }
}

public enum CATResponse {
    /// Returns the characters between the command prefix and the trailing `;`.
    public static func body(of response: String, command: String) -> String? {
        let t = TX500Protocol.CAT.terminatorString
        guard response.hasPrefix(command), response.hasSuffix(t) else { return nil }
        return String(response.dropFirst(command.count).dropLast(t.count))
    }

    /// Parses the numeric body of e.g. `PC010;` → 10, `AG0168;` with prefix `AG0` → 168.
    public static func integer(_ response: String, prefix: String) -> Int? {
        body(of: response, command: prefix).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// Snapshot of what the Radio tab shows.
public struct RigState: Equatable, Sendable {
    public var vfoA: Int?
    public var vfoB: Int?
    public var info: InformationFrame?
    public var sMeter: Int?
    /// Front-panel units (see `TX500Protocol.CAT.Levels`), not raw CAT values.
    public var powerPercent: Int?
    public var afGain: Int?
    public var rfGainDB: Int?
    public var squelch: Int?
    public var keyerCPM: Int?
    public var vox: Bool?
    public var noiseBlanker: Bool?
    public var noiseReduction: Bool?
    public var locked: Bool?

    // Lab599 extension readings (answer in TS-2000 mode too).
    public var supplyVolts: Double?
    public var agcTimeConstant: Int?
    /// Zero-based RX / TX filter preset (FIL1 = 0).
    public var rxFilterPreset: Int?
    public var txFilterPreset: Int?
    /// Whether the TX monitor is audible: CAT `MO` reads 0 when it is on and 1 when it is muted.
    public var monitorOn: Bool?
    /// TX monitor volume from CAT `ML` (000-250). Separate from `monitorOn`, which is the mute
    /// switch — the monitor can be switched on and still be inaudible at level 0.
    public var monitorLevel: Int?
    public var compressorOn: Bool?
    public var preampOn: Bool?
    public var attenuatorOn: Bool?
    public var notchOn: Bool?
    public var ritOn: Bool?
    public var xitOn: Bool?
    public var splitOn: Bool?

    public init() {}

    public var frequencyHz: Int? { info?.frequencyHz ?? vfoA }
    public var mode: OperatingMode? { info?.mode }
    public var transmitting: Bool { info?.transmitting ?? false }
}

public enum FrequencyFormat {
    private static let hzPerKHz = 1_000
    private static let hzPerMHz = 1_000_000
    /// A single-dot entry below this is read as MHz ("14.074"), otherwise as kHz ("7074.5").
    private static let mhzEntryCeiling = 1_000.0

    /// 14025900 → "14.025.900"
    public static func dotted(_ hz: Int) -> String {
        String(format: "%d.%03d.%03d", hz / hzPerMHz, (hz / hzPerKHz) % hzPerKHz, hz % hzPerKHz)
    }

    /// Accepts "14.025.900", "14.0259" (MHz), "7074.5" (kHz), "14025900" (Hz).
    public static func parse(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        switch t.filter({ $0 == "." }).count {
        case 0: return Int(t)
        case 1:
            guard let v = Double(t) else { return nil }
            let scale = v < mhzEntryCeiling ? hzPerMHz : hzPerKHz
            return Int((v * Double(scale)).rounded())
        default: return Int(t.replacingOccurrences(of: ".", with: ""))
        }
    }
}
