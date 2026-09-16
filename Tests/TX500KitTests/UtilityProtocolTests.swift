import XCTest
@testable import TX500Kit

final class SettingsBackupTests: XCTestCase {
    func testReadCommandAndParse() {
        XCTAssertEqual(SettingsBackup.readCommand(index: 0), "XL1000;")
        XCTAssertEqual(SettingsBackup.readCommand(index: 1023), "XL2023;")
        XCTAssertEqual(SettingsBackup.parseReadResponse("XL085;"), 85)
        XCTAssertEqual(SettingsBackup.parseReadResponse("XL000;"), 0)
        XCTAssertNil(SettingsBackup.parseReadResponse("XL1000;"))
        XCTAssertNil(SettingsBackup.parseReadResponse(""))
    }

    func testWriteCommandMatchesVendorFormat() {
        XCTAssertEqual(SettingsBackup.writeCommand(index: 1, value: 170), "XS1001 170;")
        XCTAssertEqual(SettingsBackup.writeCommand(index: 0, value: 5), "XS1000 5;")
    }

    func testReadAllSettings() async throws {
        var responses: [String: String] = ["ID;": "ID500;"]    // batch-read sentinel
        for i in 0..<TX500Protocol.Settings.byteCount {
            // Byte 0/1 are the table's 55 AA signature, as on a real radio; the rest counts up.
            let value = i < 2 ? Int(TX500Protocol.Settings.signature[i]) : i % 256
            responses[SettingsBackup.readCommand(index: i)] = String(format: "XL%03d;", value)
        }
        let cat = KenwoodCAT(transport: MockTransport(responses: responses))
        let backup = try await cat.readSettings()
        XCTAssertEqual(backup.bytes.count, TX500Protocol.Settings.byteCount)
        XCTAssertEqual(backup.bytes[255], 255)
        XCTAssertEqual(backup.bytes[256], 0)
        XCTAssertEqual(try SettingsBackup(fileData: backup.fileData), backup)
    }

    func testRejectsWrongSize() {
        XCTAssertThrowsError(try SettingsBackup(bytes: [0, 1, 2]))
    }
}

final class MemoryChannelTests: XCTestCase {
    // Captured from the radio: empty channel 01.
    let emptyRecord = "MR000100000000000200000000000000000000000        ;"

    func testParseEmptyChannel() throws {
        let ch = try XCTUnwrap(MemoryChannel(response: emptyRecord))
        XCTAssertEqual(ch.number, 1)
        XCTAssertTrue(ch.isEmpty)
        XCTAssertEqual(ch.mode, .usb)
        XCTAssertEqual(ch.preAtt, .off)
        XCTAssertEqual(ch.name, "")
    }

    func testWriteCommandRoundTripsThroughParser() throws {
        let ch = MemoryChannel(number: 42, frequencyHz: 14_074_000, mode: .dig, preAtt: .preamp)
        let command = ch.writeCommand
        XCTAssertEqual(command.count, TX500Protocol.Memory.recordLength)
        XCTAssertEqual(command, "MW004200014074000610000000000000000000000        ;")
        let readBack = "MR" + command.dropFirst(TX500Protocol.CAT.commandPrefixLength)
        XCTAssertEqual(MemoryChannel(response: readBack), ch)
    }

    func testMemFileRoundTrip() throws {
        let channels = [
            MemoryChannel(number: 0, frequencyHz: 7_074_000, mode: .usb, preAtt: .attenuator),
            MemoryChannel(number: 99, frequencyHz: 145_500_000, mode: .fm),
        ]
        let data = MemoryFile.encode(channels)
        XCTAssertEqual(data.count, TX500Protocol.Memory.channelRange.count * TX500Protocol.Memory.fileRecordSize)
        // Mode and PRE/ATT are ASCII digits, not raw values: USB and attenuator both store '2'
        // (0x32). Checked against a .mem file written by Lab599's own TRXMem — see
        // MemoryFileCompatibilityTests.
        XCTAssertEqual([UInt8](data.prefix(6)), [0xD0, 0xF0, 0x6B, 0x00, UInt8(ascii: "2"), UInt8(ascii: "2")])
        let decoded = try MemoryFile.decode(data)
        XCTAssertEqual(decoded[0], channels[0])
        XCTAssertEqual(decoded[99], channels[1])
        XCTAssertTrue(decoded[50].isEmpty)
    }
}

final class ClockTests: XCTestCase {
    func testSetCommandFormat() {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 15
        components.hour = 13; components.minute = 5; components.second = 9
        let date = Calendar.current.date(from: components)!
        XCTAssertEqual(KenwoodCAT.clockSetCommand(for: date), "TM13:05:09;")
    }

    func testUnsupportedWhenEchoed() async {
        let cat = KenwoodCAT(transport: MockTransport(responses: ["TM;": "TM;"]))
        do {
            _ = try await cat.radioTime()
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? TimeSyncError, .unsupported)
        }
    }
}

/// Simulates the loader: answers `OK` after the 16-byte header and again after the full payload.
final class LoaderMock: SerialTransport {
    enum Behavior { case healthy, silent, rejectHeader, rejectPayload }

    let behavior: Behavior
    let payloadLength: Int
    private(set) var received = Data()
    private var pending = Data()

    init(behavior: Behavior, payloadLength: Int) {
        self.behavior = behavior
        self.payloadLength = payloadLength
    }

    func write(_ data: Data) throws {
        let before = received.count
        received += data
        let header = TX500Protocol.Bootloader.headerLength
        if before < header && received.count >= header {
            switch behavior {
            case .healthy, .rejectPayload: pending += TX500Protocol.Bootloader.acknowledgement
            case .rejectHeader: pending += Data("ER".utf8)
            case .silent: break
            }
        }
        if received.count == header + payloadLength && before < received.count {
            pending += behavior == .rejectPayload ? Data("ER".utf8) : TX500Protocol.Bootloader.acknowledgement
        }
    }

    func read(maxCount: Int, timeout: TimeInterval) throws -> Data {
        let chunk = pending.prefix(maxCount)
        pending.removeFirst(chunk.count)
        return Data(chunk)
    }

    func drainOutput() throws {}
    func flushInput() throws {}
    func bytesAvailable() throws -> Int { pending.count }
}

final class BootloaderTests: XCTestCase {
    func makeImage(payloadLength: Int = 5_000) throws -> FirmwareImage {
        var data = TX500Protocol.Bootloader.magic
        data += Data(repeating: 0xAB, count: TX500Protocol.Bootloader.headerLength - data.count)
        data += Data((0..<payloadLength).map { UInt8($0 & 0xFF) })
        return try FirmwareImage(data: data, fileName: "mtrx9.99.00.fw")
    }

    func testRealFirmwareFileValidates() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mtrx1.30.00.fw")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "firmware file not present")
        let image = try FirmwareImage(contentsOf: url)
        XCTAssertEqual(image.data.count, 246_384)
        XCTAssertEqual(image.payload.count, 246_368)
        XCTAssertEqual(image.versionFromFileName, "1.30.00")
    }

    func testRejectsNonFirmware() {
        XCTAssertThrowsError(try FirmwareImage(data: Data(repeating: 0, count: 4_096), fileName: "x.fw")) {
            XCTAssertEqual($0 as? FirmwareImageError, .badMagic)
        }
    }

    func testHealthyUpdateSendsWholeImage() async throws {
        let image = try makeImage()
        let mock = LoaderMock(behavior: .healthy, payloadLength: image.payload.count)
        let phases = PhaseRecorder()
        try await Bootloader(transport: mock).update(image: image) { phases.append($0) }
        XCTAssertEqual(mock.received, image.data)
        XCTAssertEqual(phases.values.first, .handshaking)
        XCTAssertEqual(phases.values.last, .finished)
    }

    func testSilentLoader() async throws {
        let image = try makeImage()
        let mock = LoaderMock(behavior: .silent, payloadLength: image.payload.count)
        await assertThrows(.deviceDoesNotRespond) { try await Bootloader(transport: mock).checkHandshake(image: image) }
        XCTAssertEqual(mock.received.count, TX500Protocol.Bootloader.headerLength, "must not stream payload without OK")
    }

    func testHeaderRejected() async throws {
        let image = try makeImage()
        let mock = LoaderMock(behavior: .rejectHeader, payloadLength: image.payload.count)
        await assertThrows(.unexpectedHeaderAnswer(Data("ER".utf8))) { try await Bootloader(transport: mock).update(image: image) }
        XCTAssertEqual(mock.received.count, TX500Protocol.Bootloader.headerLength)
    }

    func testPayloadRejected() async throws {
        let image = try makeImage()
        let mock = LoaderMock(behavior: .rejectPayload, payloadLength: image.payload.count)
        await assertThrows(.updateRejected(Data("ER".utf8))) { try await Bootloader(transport: mock).update(image: image) }
    }

    private func assertThrows(_ expected: BootloaderError, _ body: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? BootloaderError, expected, file: file, line: line)
        }
    }
}

final class PhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bootloader.Phase] = []
    var values: [Bootloader.Phase] { lock.withLock { storage } }
    func append(_ p: Bootloader.Phase) { lock.withLock { storage.append(p) } }
}

/// Radio that stores `MW` writes silently (no answer) and returns them on `MR`, like the TX-500.
final class MemoryRadioMock: SerialTransport {
    private var records: [String: String] = [:]
    private var pending = Data()
    var dropWrites = false

    func write(_ data: Data) throws {
        let cmd = String(decoding: data, as: UTF8.self)
        let channel = String(cmd.dropFirst(2).prefix(4))
        if cmd.hasPrefix("MW") {
            if !dropWrites { records[channel] = "MR" + cmd.dropFirst(2) }
        } else if cmd.hasPrefix("MR") {
            let empty = MemoryChannel(number: Int(channel.suffix(2)) ?? 0).writeCommand
            pending += Data((records[channel] ?? "MR" + empty.dropFirst(2)).utf8)
        }
    }

    func read(maxCount: Int, timeout: TimeInterval) throws -> Data {
        let chunk = pending.prefix(maxCount)
        pending.removeFirst(chunk.count)
        return Data(chunk)
    }

    func drainOutput() throws {}
    func flushInput() throws {}
    func bytesAvailable() throws -> Int { pending.count }
}

final class MemoryWriteTests: XCTestCase {
    func testSilentWriteVerifiedByReadBack() async throws {
        let cat = KenwoodCAT(transport: MemoryRadioMock())
        let ch = MemoryChannel(number: 0, frequencyHz: 7_074_000, mode: .cw)
        try await cat.writeMemories([ch])
        let stored = try await cat.memoryChannel(0)
        XCTAssertEqual(stored.frequencyHz, 7_074_000)
        XCTAssertEqual(stored.mode, .cw)
    }

    func testWriteThatDidNotStoreIsReported() async {
        let mock = MemoryRadioMock()
        mock.dropWrites = true
        let cat = KenwoodCAT(transport: mock)
        do {
            try await cat.writeMemories([MemoryChannel(number: 5, frequencyHz: 14_074_000, mode: .usb)])
            XCTFail("expected notStored")
        } catch {
            XCTAssertEqual(error as? MemoryError, .notStored(channel: 5))
        }
    }
}

/// Radio settings table that accepts `XS` silently and answers `XL`.
final class SettingsRadioMock: SerialTransport {
    var table: [UInt8]
    var ignoreWrites = false
    private(set) var writeCount = 0
    private var pending = Data()

    init(table: [UInt8]) { self.table = table }

    func write(_ data: Data) throws {
        let cmd = String(decoding: data, as: UTF8.self).dropLast()
        if cmd.hasPrefix("XS") {
            writeCount += 1
            let parts = cmd.dropFirst(2).split(separator: " ")
            if !ignoreWrites, let addr = Int(parts[0]), let value = UInt8(parts[1]) { table[addr - 1000] = value }
        } else if cmd.hasPrefix("XL"), let addr = Int(cmd.dropFirst(2)) {
            pending += Data(String(format: "XL%03d;", table[addr - 1000]).utf8)
        }
    }

    func read(maxCount: Int, timeout: TimeInterval) throws -> Data {
        let chunk = pending.prefix(maxCount)
        pending.removeFirst(chunk.count)
        return Data(chunk)
    }

    func drainOutput() throws {}
    func flushInput() throws {}
    func bytesAvailable() throws -> Int { pending.count }
}

final class SettingsWriteTests: XCTestCase {
    func testWritesOnlyDifferencesAndVerifies() async throws {
        let current = try SettingsBackup(bytes: [UInt8](repeating: 7, count: TX500Protocol.Settings.byteCount))
        var targetBytes = current.bytes
        targetBytes[0x262] = 60
        targetBytes[0x274] = 4
        let target = try SettingsBackup(bytes: targetBytes)
        let mock = SettingsRadioMock(table: current.bytes)
        try await KenwoodCAT(transport: mock).writeSettings(target, current: current)
        XCTAssertEqual(mock.writeCount, 2)
        XCTAssertEqual(mock.table, targetBytes)
    }

    func testStopsWhenReadBackDiffers() async throws {
        let current = try SettingsBackup(bytes: [UInt8](repeating: 7, count: TX500Protocol.Settings.byteCount))
        var targetBytes = current.bytes
        targetBytes[10] = 1
        targetBytes[20] = 2
        let mock = SettingsRadioMock(table: current.bytes)
        mock.ignoreWrites = true
        do {
            try await KenwoodCAT(transport: mock).writeSettings(try SettingsBackup(bytes: targetBytes), current: current)
            XCTFail("expected notStored")
        } catch let SettingsBackupError.notStored(address, expected, _) {
            XCTAssertEqual(address, 1010)
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(mock.writeCount, 1, "must stop at the first unverified byte")
        }
    }
}

final class SettingsBatchReadTests: XCTestCase {
    /// Answers every `XL` in a multi-command write, in order.
    final class BatchMock: SerialTransport {
        let table: [UInt8]
        var dropEvery: Int? = nil
        private var pending = Data()
        private var answered = 0
        init(table: [UInt8]) { self.table = table }
        func write(_ data: Data) throws {
            for cmd in String(decoding: data, as: UTF8.self).split(separator: ";") {
                if cmd == "ID" { pending += Data("ID500;".utf8); continue }   // batch-read sentinel
                guard cmd.hasPrefix("XL") else { continue }
                answered += 1
                if let n = dropEvery, answered % n == 0 { continue }
                let addr = Int(cmd.dropFirst(2))! - 1000
                pending += Data(String(format: "XL%03d;", table[addr]).utf8)
            }
        }
        func read(maxCount: Int, timeout: TimeInterval) throws -> Data {
            let chunk = pending.prefix(maxCount); pending.removeFirst(chunk.count); return Data(chunk)
        }
        func drainOutput() throws {}
        func flushInput() throws { pending.removeAll() }
        func bytesAvailable() throws -> Int { pending.count }
    }

    func testBatchedReadMatchesTable() async throws {
        var table = (0..<TX500Protocol.Settings.byteCount).map { UInt8($0 % 251) }
        table.replaceSubrange(0..<2, with: TX500Protocol.Settings.signature)
        let backup = try await KenwoodCAT(transport: BatchMock(table: table)).readSettings()
        XCTAssertEqual(backup.bytes, table)
    }

    func testFallsBackToSingleReadsWhenBatchIncomplete() async throws {
        let table = (0..<TX500Protocol.Settings.byteCount).map { UInt8($0 % 7) }
        let mock = BatchMock(table: table)
        mock.dropEvery = 50   // lose one answer now and then
        let values = try await KenwoodCAT(transport: mock).readSettings(startIndex: 40, count: 16)
        XCTAssertEqual(values, Array(table[40..<56]))
    }
}

final class BackupComparisonTests: XCTestCase {
    func backup(_ changes: [Int: UInt8]) throws -> SettingsBackup {
        var bytes = [UInt8](repeating: 0, count: TX500Protocol.Settings.byteCount)
        changes.forEach { bytes[$0] = $1 }
        return try SettingsBackup(bytes: bytes)
    }

    func testSplitsConstantFromVaryingBytes() throws {
        let comparison = BackupComparison(backups: [
            try backup([0x262: 100, 0x300: 0x40]),
            try backup([0x262: 60, 0x300: 0x40]),
            try backup([0x262: 80, 0x300: 0x40]),
        ])
        XCTAssertEqual(comparison.varying, [0x262])
        XCTAssertTrue(comparison.isConstant(0x300))
        XCTAssertEqual(comparison.note(for: 0x300), "same in all 3 backups (0x40)")
        XCTAssertNil(comparison.note(for: 0x262))
    }

    func testNeedsMoreThanOneBackup() throws {
        XCTAssertFalse(BackupComparison(backups: [try backup([:])]).isUsable)
    }
}

final class RegionReadTests: XCTestCase {
    func testRegionReadMatchesFullReadAndIsSmaller() async throws {
        let table = (0..<TX500Protocol.Settings.byteCount).map { UInt8($0 % 241) }
        var responses: [String: String] = ["ID;": "ID500;"]    // batch-read sentinel
        for i in table.indices { responses[SettingsBackup.readCommand(index: i)] = String(format: "XL%03d;", table[i]) }

        let mock = MockTransport(responses: responses)
        let region = TX500Protocol.Settings.Layout.menuAreaStart..<TX500Protocol.Settings.Layout.reservedStart
        let bytes = try await KenwoodCAT(transport: mock).readSettings(range: region)
        XCTAssertEqual(bytes, Array(table[region]))
        // Only the region was requested, not the whole table.
        let requests = String(decoding: mock.written, as: UTF8.self).components(separatedBy: ";").filter { $0.hasPrefix("XL") }
        XCTAssertEqual(requests.count, region.count)

        let snapshot = try SettingsBackup.fromRegion(bytes, startingAt: region.lowerBound)
        XCTAssertEqual(snapshot.bytes[region.lowerBound], table[region.lowerBound])
        XCTAssertEqual(snapshot.bytes[0], 0, "outside the region stays zero")
    }

    func testRegionSnapshotsDiffAtRealOffsets() throws {
        let start = TX500Protocol.Settings.Layout.menuAreaStart
        var before = [UInt8](repeating: 5, count: 132)
        var after = before
        after[0x271 - start] = 9
        let a = try SettingsBackup.fromRegion(before, startingAt: start)
        let b = try SettingsBackup.fromRegion(after, startingAt: start)
        XCTAssertEqual(a.differences(from: b), [0x271])
        before[0] = 5
    }
}

final class MemoryWriteCommandTests: XCTestCase {
    /// The exact frame that a real radio accepted (tools/memwrite.py, channel 05, 14.060 MHz CW),
    /// with the channel number swapped. If our writeCommand differs from this, the app is sending
    /// something the radio will not store.
    func testWriteCommandMatchesWhatTheRadioAccepted() throws {
        let known = "MW000500014060000300000000000000000000000        ;"
        let channel = MemoryChannel(number: 5, frequencyHz: 14_060_000, mode: .cw, preAtt: .off)
        XCTAssertEqual(channel.writeCommand, known)

        let zero = MemoryChannel(number: 0, frequencyHz: 14_060_000, mode: .cw, preAtt: .off)
        XCTAssertEqual(zero.writeCommand, known.replacingOccurrences(of: "MW0005", with: "MW0000"))
    }
}

final class MemoryWriteGuardTests: XCTestCase {
    /// A half-finished edit — mode chosen, frequency never committed — used to be written as an
    /// empty channel and then pass verification, because an empty channel skips the mode check.
    /// The radio stored nothing while the app reported success.
    func testRefusesAChannelWithAModeButNoFrequency() async throws {
        let cat = KenwoodCAT(transport: MockTransport())
        let halfEdited = MemoryChannel(number: 0, frequencyHz: 0, mode: .cw, preAtt: .off)
        do {
            try await cat.writeMemories([halfEdited])
            XCTFail("expected the incomplete channel to be refused")
        } catch let error as MemoryError {
            XCTAssertEqual(error, .incomplete(channel: 0))
        }
    }

    /// Clearing a channel is still allowed: no mode and no frequency means "make this empty".
    func testAllowsClearingAChannel() throws {
        let cleared = MemoryChannel(number: 0)
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertNil(cleared.mode)
    }
}

final class MemoryFileCompatibilityTests: XCTestCase {
    /// A `.mem` file written by Lab599's own TRXMem tool, holding two channels.
    ///
    /// The frequency is a binary Int32 but mode and PRE/ATT are stored as **ASCII digits** — a CW
    /// channel is 0x33 ('3'), not 0x03. We used to write raw binary, so our files were not readable
    /// by TRXMem and its files lost their mode when imported here.
    func testReadsAFileWrittenByTheVendorTool() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "vendor-memories", withExtension: "mem", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, TX500Protocol.Memory.channelRange.count * TX500Protocol.Memory.fileRecordSize)

        let channels = try MemoryFile.decode(data)
        XCTAssertEqual(channels[0].frequencyHz, 14_065_000)
        XCTAssertEqual(channels[0].mode, .cw)
        XCTAssertEqual(channels[0].preAtt, .off)
        XCTAssertEqual(channels[5].frequencyHz, 14_060_000)
        XCTAssertEqual(channels[5].mode, .cw)
        XCTAssertTrue(channels[1].isEmpty)
        XCTAssertEqual(channels.filter { !$0.isEmpty }.count, 2)
    }

    /// Re-encoding the vendor's own file must reproduce it byte for byte, or our exports are not
    /// interchangeable with theirs.
    func testOurEncodingMatchesTheVendorFileByteForByte() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "vendor-memories", withExtension: "mem", subdirectory: "Fixtures"))
        let original = try Data(contentsOf: url)
        XCTAssertEqual(MemoryFile.encode(try MemoryFile.decode(original)), original)
    }
}

final class BaudRateTests: XCTestCase {
    /// The rates offered in Preferences. The radio is fixed at 9600, so the list exists for adapters
    /// and bridges — but it must contain the radio's own rate, and that must be the default.
    func testStandardRatesIncludeTheRadiosOwn() {
        XCTAssertTrue(TX500Protocol.CAT.standardBaudRates.contains(TX500Protocol.CAT.baudRate))
        XCTAssertEqual(TX500Protocol.CAT.standardBaudRates, TX500Protocol.CAT.standardBaudRates.sorted())
        // The bootloader's speed is fixed by the loader protocol and is not a user preference.
        XCTAssertNotEqual(TX500Protocol.Bootloader.baudRate, TX500Protocol.CAT.baudRate)
    }

    /// A stored preference is narrowed to something we actually offer: an unset default of 0, or a
    /// stale value from an older build, must not leave the app unable to open the port.
    func testUnsupportedStoredRateFallsBackToTheRadiosOwn() {
        XCTAssertEqual(TX500Protocol.CAT.supportedBaudRate(0), TX500Protocol.CAT.baudRate)
        XCTAssertEqual(TX500Protocol.CAT.supportedBaudRate(7777), TX500Protocol.CAT.baudRate)
        XCTAssertEqual(TX500Protocol.CAT.supportedBaudRate(-1), TX500Protocol.CAT.baudRate)
        XCTAssertEqual(TX500Protocol.CAT.supportedBaudRate(19200), 19200)
    }
}
