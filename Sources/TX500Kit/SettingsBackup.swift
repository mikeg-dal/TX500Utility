import Foundation

public enum SettingsBackupError: Error, LocalizedError, Equatable {
    case wrongSize(Int)
    case badSignature(UInt8, UInt8)
    case readFailed(address: Int, response: String)
    case notStored(address: Int, expected: UInt8, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .wrongSize(n): "Settings file must be \(TX500Protocol.Settings.byteCount) bytes (got \(n))"
        case let .badSignature(a, b):
            "The radio's answers didn't line up: the settings table should start with 55 AA but read "
                + String(format: "%02X %02X", a, b) + ". Nothing was saved — try again."
        case let .readFailed(a, r): "Radio gave an unexpected answer reading setting \(a): \(r.isEmpty ? "no answer" : r)"
        case let .notStored(a, e, r): "Setting \(a) did not read back as \(e) (radio answered \(r.isEmpty ? "nothing" : r)). The restore stopped; your safety backup is in the list."
        }
    }
}

/// The radio's 1024-byte settings table, as read with `XL` and saved in TRXSettings `.set` files.
public struct SettingsBackup: Equatable, Sendable {
    public private(set) var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == TX500Protocol.Settings.byteCount else { throw SettingsBackupError.wrongSize(bytes.count) }
        self.bytes = bytes
    }

    /// A backup holding only `region` (everything else zero), so two region reads can be compared
    /// with the same tools as full backups and still report real offsets.
    public static func fromRegion(_ bytes: [UInt8], startingAt start: Int) throws -> SettingsBackup {
        var full = [UInt8](repeating: 0, count: TX500Protocol.Settings.byteCount)
        for (offset, value) in bytes.enumerated() { full[start + offset] = value }
        return try SettingsBackup(bytes: full)
    }

    public init(fileData: Data) throws {
        try self.init(bytes: [UInt8](fileData))
    }

    public var fileData: Data { Data(bytes) }

    /// Indices whose values differ between two backups.
    public func differences(from other: SettingsBackup) -> [Int] {
        bytes.indices.filter { bytes[$0] != other.bytes[$0] }
    }

    public static func address(ofIndex index: Int) -> Int { TX500Protocol.Settings.firstAddress + index }

    static func readCommand(index: Int) -> String {
        TX500Protocol.Settings.readCommand + String(address(ofIndex: index)) + TX500Protocol.CAT.terminatorString
    }

    static func writeCommand(index: Int, value: UInt8) -> String {
        TX500Protocol.Settings.writeCommand + String(address(ofIndex: index))
            + TX500Protocol.Settings.writeSeparator + String(value) + TX500Protocol.CAT.terminatorString
    }

    /// `XL085;` → 85
    static func parseReadResponse(_ response: String) -> UInt8? {
        guard let body = CATResponse.body(of: response, command: TX500Protocol.Settings.readCommand),
              body.count == TX500Protocol.Settings.valueDigits else { return nil }
        return UInt8(body)
    }
}

public typealias ProgressHandler = @Sendable (_ completed: Int, _ total: Int) -> Void

extension KenwoodCAT {
    /// Reads all 1024 settings bytes (`XL1000;` … `XL2023;`). Read-only.
    public func readSettings(progress: ProgressHandler? = nil) throws -> SettingsBackup {
        let total = TX500Protocol.Settings.byteCount
        var bytes = [UInt8]()
        bytes.reserveCapacity(total)
        var index = 0
        while index < total {
            let count = min(TX500Protocol.Settings.readBatchSize, total - index)
            bytes += try readSettings(startIndex: index, count: count)
            index += count
            progress?(index, total)
        }
        // A misaligned read looks like perfectly ordinary data, so check the one value we know:
        // every table starts with 55 AA. Better to fail than to save a backup that would restore
        // every setting to its neighbour's value.
        let signature = TX500Protocol.Settings.signature
        guard Array(bytes.prefix(signature.count)) == signature else {
            throw SettingsBackupError.badSignature(bytes[0], bytes[1])
        }
        return try SettingsBackup(bytes: bytes)
    }

    /// Reads `count` consecutive settings bytes by sending all `XL` requests in one write and reading
    /// the answers in order (~4.5× faster than one at a time on the TX-500). If any answer in the batch
    /// is wrong or missing, the batch is re-read one byte at a time.
    /// Reads `count` bytes in one batch, anchored by an `ID;` sentinel.
    ///
    /// `XL` answers carry no address — `XL085;` says "85" and nothing about which byte — so a late
    /// answer to an earlier command is indistinguishable from this batch's first byte and would
    /// shift every byte after it, silently. The radio answers in order, so the sentinel pins the
    /// end: our bytes are the last `count` `XL` frames before the `ID` answer, and anything ahead of
    /// them is stale. The sentinel goes in its own write because the radio queues only
    /// `readBatchSize` commands and a further one in the same write costs an answer.
    public func readSettings(startIndex: Int, count: Int) throws -> [UInt8] {
        let commands = (startIndex..<(startIndex + count)).map { SettingsBackup.readCommand(index: $0) }
        try transport.flushInput()
        try transport.write(Data(commands.joined().utf8))
        try transport.write(Data(TX500Protocol.Settings.sentinelCommand.utf8))

        var values: [UInt8] = []
        var sawSentinel = false
        let deadline = Date().addingTimeInterval(TX500Protocol.Settings.replyTimeout * Double(count + 2))
        while deadline.timeIntervalSinceNow > 0 {
            let data = try transport.read(until: TX500Protocol.CAT.terminator,
                                          timeout: TX500Protocol.Settings.replyTimeout)
            if data.isEmpty { break }
            let frame = String(decoding: data, as: UTF8.self)
            if frame.hasPrefix(TX500Protocol.Settings.sentinelPrefix) { sawSentinel = true; break }
            if let value = SettingsBackup.parseReadResponse(frame) { values.append(value) }
        }
        if sawSentinel, values.count >= count { return Array(values.suffix(count)) }

        // Missing answers or no sentinel: fall back to one read at a time, which cannot get out of step.
        try (transport as? SerialPort)?.discardStaleInput()
        return try (startIndex..<(startIndex + count)).map { try readSetting(index: $0) }
    }

    /// Reads a slice of the settings table (batched). Much faster than the whole table when only one
    /// area can change — the menu area is 132 bytes (~2 s) versus 1024 (~12 s).
    public func readSettings(range: Range<Int>, progress: ProgressHandler? = nil) throws -> [UInt8] {
        var values: [UInt8] = []
        values.reserveCapacity(range.count)
        var index = range.lowerBound
        while index < range.upperBound {
            let count = min(TX500Protocol.Settings.readBatchSize, range.upperBound - index)
            values += try readSettings(startIndex: index, count: count)
            index += count
            progress?(values.count, range.count)
        }
        return values
    }

    /// Reads one settings byte (`XL<1000+index>;`). One actor call per byte, so callers that loop
    /// over this let other CAT traffic (e.g. live polling) run in between.
    public func readSetting(index: Int) throws -> UInt8 {
        let response = try raw(SettingsBackup.readCommand(index: index), timeout: TX500Protocol.Settings.replyTimeout)
        guard let value = SettingsBackup.parseReadResponse(response) else {
            throw SettingsBackupError.readFailed(address: SettingsBackup.address(ofIndex: index), response: response)
        }
        return value
    }

    /// Writes the bytes of `target` that differ from `current` with `XS`, verifying each by reading
    /// it back with `XL`. Changes the radio's configuration — callers must confirm with the user and
    /// pass a fresh read of the radio as `current` (which also serves as the safety backup).
    ///
    /// A reply to `XS` is not required: the radio may stay silent (as it does for `MW` in TS-2000
    /// mode), so any reply is read and discarded and the read-back is the source of truth.
    public func writeSettings(_ target: SettingsBackup, current: SettingsBackup, progress: ProgressHandler? = nil) throws {
        let indices = target.differences(from: current)
        for (done, index) in indices.enumerated() {
            let value = target.bytes[index]
            try transport.flushInput()
            try transport.write(Data(SettingsBackup.writeCommand(index: index, value: value).utf8))
            try transport.drainOutput()
            _ = try transport.read(exactly: TX500Protocol.Settings.writeReplyLength, timeout: TX500Protocol.Settings.optionalReplyWait)
            let readBack = try raw(SettingsBackup.readCommand(index: index), timeout: TX500Protocol.Settings.replyTimeout)
            guard SettingsBackup.parseReadResponse(readBack) == value else {
                throw SettingsBackupError.notStored(address: SettingsBackup.address(ofIndex: index), expected: value, actual: readBack)
            }
            progress?(done + 1, indices.count)
        }
    }
}
