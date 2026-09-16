import Foundation

/// How sure we are about a decoded settings field.
public enum FieldConfidence: String, Codable, Sendable, CaseIterable, Comparable {
    /// Verified by a controlled change (taught, CAT-verified, or matched across differing CAT values).
    case confirmed
    /// Strongly suggested by the data (values match manual defaults or a single CAT reading) but not yet verified.
    case inferred
    /// Raw bytes with no known meaning yet.
    case unknown

    private var rank: Int {
        switch self {
        case .unknown: 0
        case .inferred: 1
        case .confirmed: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// One named region of the 1024-byte settings table. Codable so discoveries can be saved as JSON.
public struct SettingsField: Codable, Sendable, Identifiable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case uint8
        case uint16
        case uint32
        /// UInt32 LE in Hz, shown as MHz.
        case frequencyHz
        /// Raw bytes shown as hex.
        case bytes
        /// Unused area; shown as "all zero" or a count of non-zero bytes.
        case reserved
    }

    public var id: Int { offset }
    public var group: String
    public var name: String
    public var offset: Int
    public var kind: Kind
    public var length: Int
    public var confidence: FieldConfidence
    /// Why we believe this (shown as a tooltip), e.g. "Matched CAT MG across 2 loads".
    public var note: String
    /// Displayed value = raw × scale + displayOffset (e.g. 0.1 for "0.9" stored as 9).
    public var scale: Double
    /// Added after scaling, for settings the radio stores on a shifted or inverted scale:
    /// RF gain shows 5 − byte (byte 6 reads −1 dB), and NR level shows byte − 1.
    public var displayOffset: Double
    public var unit: String
    /// Interpret the raw value as two's complement (e.g. pan shift −100…+100).
    public var signed: Bool
    /// Which bits of the byte this field owns, when the radio packs several settings into one.
    /// `0...2` is CW weight in the low three bits of `0x276`; `4...4` is a single flag bit.
    /// Bits are numbered from 0 = least significant, and the value is shifted down to start at 0.
    public var bits: ClosedRange<Int>?
    /// What the stored numbers mean, e.g. `[0: "2:1", 1: "2.5:1"]` or `[0: "Off", 1: "On"]`.
    /// Values not listed fall back to the number itself.
    public var values: [Int: String]?
    public var updated: Date?

    public init(group: String, name: String, offset: Int, kind: Kind, length: Int? = nil,
                confidence: FieldConfidence, note: String = "", scale: Double = 1, unit: String = "",
                signed: Bool = false, bits: ClosedRange<Int>? = nil, values: [Int: String]? = nil,
                displayOffset: Double = 0, updated: Date? = nil) {
        self.bits = bits
        self.values = values
        self.displayOffset = displayOffset
        self.group = group
        self.name = name
        self.offset = offset
        self.kind = kind
        self.length = length ?? Self.naturalLength(of: kind)
        self.confidence = confidence
        self.note = note
        self.scale = scale
        self.unit = unit
        self.signed = signed
        self.updated = updated
    }

    public static func naturalLength(of kind: Kind) -> Int {
        switch kind {
        case .uint8, .bytes, .reserved: MemoryLayout<UInt8>.size
        case .uint16: MemoryLayout<UInt16>.size
        case .uint32, .frequencyHz: MemoryLayout<UInt32>.size
        }
    }

    public var range: Range<Int> { offset..<(offset + length) }

    /// `XL` address of the first byte.
    public var catAddress: Int { SettingsBackup.address(ofIndex: offset) }

    /// The bits this field occupies, as a mask over its byte (all bits when it owns the whole byte).
    public var bitMask: Int {
        guard let bits else { return (1 << (length * UInt8.bitWidth)) - 1 }
        return ((1 << bits.count) - 1) << bits.lowerBound
    }

    /// Little-endian unsigned value of the field's bytes, narrowed to `bits` when it shares a byte.
    public func rawValue(in bytes: [UInt8]) -> Int {
        let whole = range.reversed().reduce(0) { ($0 << UInt8.bitWidth) | Int(bytes[$1]) }
        guard let bits else { return whole }
        return (whole >> bits.lowerBound) & ((1 << bits.count) - 1)
    }

    /// Raw value with sign applied when `signed`.
    public func integerValue(in bytes: [UInt8]) -> Int {
        let raw = rawValue(in: bytes)
        guard signed else { return raw }
        let bits = length * UInt8.bitWidth
        let signBit = 1 << (bits - 1)
        return raw & signBit != 0 ? raw - (1 << bits) : raw
    }

    public func hex(in bytes: [UInt8]) -> String {
        bytes[range].map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public func formattedValue(in bytes: [UInt8]) -> String {
        switch kind {
        case .frequencyHz:
            return FrequencyFormat.dotted(rawValue(in: bytes)) + " MHz"
        case .bytes:
            return hex(in: bytes)
        case .reserved:
            let nonZero = bytes[range].filter { $0 != 0 }.count
            return nonZero == 0 ? "all zero (\(length) bytes)" : "\(nonZero) non-zero of \(length) bytes"
        case .uint8, .uint16, .uint32:
            if let names = values, let name = names[rawValue(in: bytes)] { return name }
            let value = Double(integerValue(in: bytes)) * scale + displayOffset
            // Only a fractional scale needs decimals; a negative one (RF gain counts down) does not.
            let decimals = (scale > 0 && scale < 1) ? max(0, Int((-log10(scale)).rounded(.up))) : 0
            let number = String(format: "%.\(decimals)f", value)
            return unit.isEmpty ? number : "\(number) \(unit)"
        }
    }
}
