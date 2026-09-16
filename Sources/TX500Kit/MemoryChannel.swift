import Foundation

public enum MemoryError: Error, LocalizedError, Equatable {
    case malformedRecord(channel: Int, response: String)
    case invalidChannel(Int)
    case wrongFileSize(Int)
    case notStored(channel: Int)
    case incomplete(channel: Int)

    public var errorDescription: String? {
        switch self {
        case let .malformedRecord(c, r): "Unexpected answer reading memory \(c): \(r.isEmpty ? "no answer" : r)"
        case let .invalidChannel(c): "Memory channel \(c) is out of range"
        case let .wrongFileSize(n): "Memory file has the wrong size (\(n) bytes)"
        case let .notStored(c): "Memory \(c) did not read back as written. Check it on the radio and try again."
        case let .incomplete(c): "Memory \(c) has a mode but no frequency, so there is nothing to store. Enter a frequency, or clear the channel to empty it."
        }
    }
}

/// Front-end preamp / attenuator state stored with a memory channel.
public enum PreAtt: Int, CaseIterable, Sendable, Identifiable {
    case off = 0, preamp = 1, attenuator = 2

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .off: "—"
        case .preamp: "PRE"
        case .attenuator: "ATT"
        }
    }
}

/// One memory channel (00–99). A frequency of 0 means the channel is empty.
public struct MemoryChannel: Equatable, Sendable, Identifiable {
    private typealias M = TX500Protocol.Memory

    public var id: Int { number }
    public let number: Int
    public var frequencyHz: Int
    public var mode: OperatingMode?
    public var preAtt: PreAtt
    public var name: String

    public init(number: Int, frequencyHz: Int = 0, mode: OperatingMode? = nil, preAtt: PreAtt = .off, name: String = "") {
        self.number = number
        self.frequencyHz = frequencyHz
        self.mode = mode
        self.preAtt = preAtt
        self.name = name
    }

    public var isEmpty: Bool { frequencyHz == 0 }

    // MARK: CAT encoding

    static func channelField(_ number: Int) -> String {
        M.bankPrefix + KenwoodCAT.zeroPadded(number, digits: M.channelDigits)
    }

    static func readCommand(_ number: Int) -> String {
        M.readCommand + channelField(number) + TX500Protocol.CAT.terminatorString
    }

    /// `MW00cc` + freq(11) + mode + preAtt + 22 zeros + 8 spaces + `;` — identical to TRXMem.
    var writeCommand: String {
        M.writeCommand + Self.channelField(number)
            + KenwoodCAT.zeroPadded(frequencyHz, digits: M.frequencyDigits)
            + String(mode?.rawValue ?? 0)
            + String(preAtt.rawValue)
            + String(repeating: "0", count: M.reservedDigits)
            + String(repeating: " ", count: M.nameLength)
            + TX500Protocol.CAT.terminatorString
    }

    /// Parses an `MR` answer, e.g. `MR000100000000000200000000000000000000000        ;`.
    init?(response: String) {
        guard response.count == M.recordLength,
              let body = CATResponse.body(of: response, command: M.readCommand) else { return nil }
        let chars = Array(body)
        let headerDigits = M.Layout.headerLength - TX500Protocol.CAT.commandPrefixLength
        guard let number = Int(String(chars[(headerDigits - M.channelDigits)..<headerDigits])) else { return nil }
        let record = Array(chars.dropFirst(headerDigits))
        guard let freq = Int(String(record[M.Layout.frequency])) else { return nil }
        self.number = number
        frequencyHz = freq
        mode = Int(String(record[M.Layout.mode])).flatMap(OperatingMode.init(rawValue:))
        preAtt = Int(String(record[M.Layout.preAtt])).flatMap(PreAtt.init(rawValue:)) ?? .off
        name = String(record[M.Layout.name]).trimmingCharacters(in: .whitespaces)
    }
}

/// TRXMem-compatible `.mem` file.
public enum MemoryFile {
    private typealias M = TX500Protocol.Memory
    private static var channelCount: Int { M.channelRange.count }

    public static func encode(_ channels: [MemoryChannel]) -> Data {
        var data = Data(capacity: channelCount * M.fileRecordSize)
        let byNumber = Dictionary(uniqueKeysWithValues: channels.map { ($0.number, $0) })
        for number in M.channelRange {
            let ch = byNumber[number] ?? MemoryChannel(number: number)
            withUnsafeBytes(of: Int32(truncatingIfNeeded: ch.frequencyHz).littleEndian) { data.append(contentsOf: $0) }
            data.append(M.fileDigit(ch.mode?.rawValue ?? 0))
            data.append(M.fileDigit(ch.preAtt.rawValue))
        }
        return data
    }

    public static func decode(_ data: Data) throws -> [MemoryChannel] {
        guard data.count == channelCount * M.fileRecordSize else { throw MemoryError.wrongFileSize(data.count) }
        let bytes = [UInt8](data)
        return M.channelRange.map { number in
            let base = number * M.fileRecordSize
            let freq = bytes[base..<(base + MemoryLayout<Int32>.size)].enumerated()
                .reduce(UInt32(0)) { $0 | UInt32($1.element) << (UInt32($1.offset) * UInt32(UInt8.bitWidth)) }
            let modeValue = M.fileValue(bytes[base + MemoryLayout<Int32>.size])
            let preAttValue = M.fileValue(bytes[base + MemoryLayout<Int32>.size + 1])
            return MemoryChannel(number: number,
                                 frequencyHz: Int(Int32(bitPattern: freq)),
                                 mode: OperatingMode(rawValue: modeValue),
                                 preAtt: PreAtt(rawValue: preAttValue) ?? .off)
        }
    }
}

extension KenwoodCAT {
    /// Reads one memory channel. Read-only.
    public func memoryChannel(_ number: Int) throws -> MemoryChannel {
        guard TX500Protocol.Memory.channelRange.contains(number) else { throw MemoryError.invalidChannel(number) }
        let response = try raw(MemoryChannel.readCommand(number))
        guard let ch = MemoryChannel(response: response) else {
            throw MemoryError.malformedRecord(channel: number, response: response)
        }
        return ch
    }

    /// Reads all 100 channels. Read-only.
    public func readMemories(progress: ProgressHandler? = nil) throws -> [MemoryChannel] {
        let range = TX500Protocol.Memory.channelRange
        return try range.map { number in
            let ch = try memoryChannel(number)
            progress?(number - range.lowerBound + 1, range.count)
            return ch
        }
    }

    /// Writes memory channels. Changes the radio — callers must confirm with the user first.
    ///
    /// `MW` is a set command and the TX-500 sends no answer, so each channel is verified by
    /// reading it back with `MR` and comparing frequency, mode and PRE/ATT.
    public func writeMemories(_ channels: [MemoryChannel], progress: ProgressHandler? = nil) throws {
        for (offset, ch) in channels.enumerated() {
            guard TX500Protocol.Memory.channelRange.contains(ch.number) else { throw MemoryError.invalidChannel(ch.number) }
            // A channel with a mode but no frequency is not something anyone means to write: it is
            // what a half-finished edit looks like. Writing it stores nothing, and because the
            // radio then reads back as empty, the verification below would call that a success.
            guard !(ch.isEmpty && ch.mode != nil) else { throw MemoryError.incomplete(channel: ch.number) }
            try send(ch.writeCommand)
            Thread.sleep(forTimeInterval: TX500Protocol.Memory.writeSettleDelay)
            let stored = try memoryChannel(ch.number)
            guard stored.frequencyHz == ch.frequencyHz,
                  stored.preAtt == ch.preAtt,
                  ch.isEmpty || stored.mode == ch.mode else {
                throw MemoryError.notStored(channel: ch.number)
            }
            progress?(offset + 1, channels.count)
        }
    }
}
