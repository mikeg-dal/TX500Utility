import XCTest
@testable import TX500Kit

/// Scripted transport: maps each written command to the bytes the radio would send back.
final class MockTransport: SerialTransport {
    var responses: [String: String]
    var written = Data()
    private var pending = Data()

    init(responses: [String: String] = [:], stale: String = "") {
        self.responses = responses
        pending = Data(stale.utf8)
    }

    func write(_ data: Data) throws {
        written += data
        // A single write may carry several commands (batched reads); answer each in order.
        for cmd in String(decoding: data, as: UTF8.self).split(separator: ";", omittingEmptySubsequences: true) {
            if let r = responses[cmd + ";"] { pending += Data(r.utf8) }
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

final class CATTests: XCTestCase {
    // Captured from the connected TX-500 on 2026-09-15.
    let captured: [String: String] = [
        "ID;": "ID019;",
        "FA;": "FA00014025900;",
        "FB;": "FB00010100000;",
        "MD;": "MD3;",
        "IF;": "IF00014025900     +000000000030000000;",
        "SM0;": "SM00000;",
        "PC;": "PC010;",
        "AG0;": "AG0168;",
        "RG;": "RG090;",
        "SQ0;": "SQ0000;",
        "KS;": "KS100;",
        "VX;": "VX1;",
        "NB;": "NB0;",
        "NR;": "NR0;",
        "LK;": "LK00;",
        "FN;": "FN;",
    ]

    func testInformationFrame() throws {
        let f = try XCTUnwrap(InformationFrame(response: "IF00014025900     +000000000030000000;"))
        XCTAssertEqual(f.frequencyHz, 14_025_900)
        XCTAssertEqual(f.mode, .cw)
        XCTAssertFalse(f.transmitting)
        XCTAssertFalse(f.split)
        XCTAssertEqual(f.ritOffsetHz, 0)
        XCTAssertEqual(f.vfo, 0)
    }

    /// Reproduces the connect failure: a stale reply in the adapter buffer must not be taken as
    /// the answer, and must not shift later answers.
    func testStaleFrameIsSkipped() async throws {
        let cat = KenwoodCAT(transport: MockTransport(responses: captured, stale: "MD3;"))
        let id = try await cat.identify()
        XCTAssertEqual(id, "ID019;")
        let info = try await cat.information()
        XCTAssertEqual(info.frequencyHz, 14_025_900)
    }

    func testInformationFrameRejectsGarbage() {
        XCTAssertNil(InformationFrame(response: "IF;"))
        XCTAssertNil(InformationFrame(response: "FA00014025900;"))
    }

    func testReadState() async throws {
        let cat = KenwoodCAT(transport: MockTransport(responses: captured))
        let s = try await cat.readState()
        XCTAssertEqual(s.vfoA, 14_025_900)
        XCTAssertEqual(s.vfoB, 10_100_000)
        XCTAssertEqual(s.mode, .cw)
        XCTAssertEqual(s.powerPercent, 10)
        XCTAssertEqual(s.afGain, 67)      // AG0168
        XCTAssertEqual(s.rfGainDB, -1)    // RG090
        XCTAssertEqual(s.keyerCPM, 100)
        XCTAssertEqual(s.vox, true)
        XCTAssertEqual(s.sMeter, 0)
        XCTAssertEqual(s.locked, false)
    }

    func testEchoMeansUnsupported() async throws {
        let cat = KenwoodCAT(transport: MockTransport(responses: captured))
        do {
            _ = try await cat.query("FN")
            XCTFail("expected unsupported")
        } catch let e as CATError {
            XCTAssertEqual(e, .unsupported("FN;"))
        }
    }

    func testSettersFormatCommands() async throws {
        let mock = MockTransport()
        let cat = KenwoodCAT(transport: mock)
        try await cat.setFrequency(14_030_000)
        try await cat.setMode(.usb)
        try await cat.setPower(percent: 50)
        try await cat.setAFGain(100)
        try await cat.setRFGain(dB: 0)
        try await cat.setKeyerSpeed(cpm: 120)
        XCTAssertEqual(String(decoding: mock.written, as: UTF8.self),
                       "FA00014030000;MD2;PC050;AG0250;RG092;KS120;")
    }

    /// Calibration points logged from the radio while sweeping its controls.
    func testLevelScalesMatchRadio() {
        let L = TX500Protocol.CAT.Levels.self
        XCTAssertEqual(L.powerPercent.display(fromRaw: 10), 10)
        XCTAssertEqual(L.powerPercent.display(fromRaw: 100), 100)
        XCTAssertEqual(L.afGain.display(fromRaw: 0), 0)
        XCTAssertEqual(L.afGain.display(fromRaw: 250), 100)
        XCTAssertEqual(L.afGain.raw(fromDisplay: 50), 125)
        XCTAssertEqual(L.rfGain.display(fromRaw: 0), -51)
        XCTAssertEqual(L.rfGain.display(fromRaw: 92), 0)
        XCTAssertEqual(L.rfGain.display(fromRaw: 100), 5)
        XCTAssertEqual(L.rfGain.raw(fromDisplay: 0), 92)
        XCTAssertEqual(L.rfGain.raw(fromDisplay: -51), 0)
        XCTAssertEqual(L.rfGain.raw(fromDisplay: 5), 100)
        XCTAssertEqual(L.keyerSpeed.display(fromRaw: 300), 300)
        XCTAssertEqual(L.keyerSpeed.display(fromRaw: 10), 10)
    }

    func testSetterRejectsOutOfRange() async {
        let cat = KenwoodCAT(transport: MockTransport())
        do {
            try await cat.setPower(percent: 5)
            XCTFail("expected invalid argument")
        } catch {
            XCTAssertTrue(error is CATError)
        }
    }

    /// A settings table where every byte equals its own index, so a shift of one is obvious.
    private func settingsResponses(signature: [UInt8] = TX500Protocol.Settings.signature) -> [String: String] {
        var responses = ["ID;": "ID500;"]
        for index in 0..<TX500Protocol.Settings.byteCount {
            let value = index < signature.count ? signature[index] : UInt8(index % 256)
            responses[SettingsBackup.readCommand(index: index)] = String(format: "XL%03d;", Int(value))
        }
        return responses
    }

    /// `XL` answers carry no address, so a late answer to an earlier read is indistinguishable from
    /// this batch's first byte. The `ID;` sentinel pins the end of the batch so the stale one is
    /// dropped instead of shifting all 1024 bytes by one.
    func testStaleAnswerDoesNotShiftSettingsRead() async throws {
        let cat = KenwoodCAT(transport: MockTransport(responses: settingsResponses(), stale: "XL099;"))
        let values = try await cat.readSettings(startIndex: 0, count: 16)
        XCTAssertEqual(values.prefix(2), TX500Protocol.Settings.signature[...])
        XCTAssertEqual(Array(values.suffix(3)), [13, 14, 15])
    }

    func testFullReadRejectsMisalignedTable() async throws {
        // The table reads back without its 55 AA signature: a shifted read, not real data.
        let cat = KenwoodCAT(transport: MockTransport(responses: settingsResponses(signature: [0x55, 0x55])))
        do {
            _ = try await cat.readSettings()
            XCTFail("expected a bad-signature error rather than a silently corrupt backup")
        } catch let error as SettingsBackupError {
            XCTAssertEqual(error, .badSignature(0x55, 0x55))
        }
    }

    func testFullReadAcceptsAValidTable() async throws {
        let cat = KenwoodCAT(transport: MockTransport(responses: settingsResponses()))
        let backup = try await cat.readSettings()
        XCTAssertEqual(backup.bytes.count, TX500Protocol.Settings.byteCount)
        XCTAssertEqual(Array(backup.bytes.prefix(2)), TX500Protocol.Settings.signature)
    }

    func testFrequencyFormatting() {
        XCTAssertEqual(FrequencyFormat.dotted(14_025_900), "14.025.900")
        XCTAssertEqual(FrequencyFormat.parse("14.025.900"), 14_025_900)
        XCTAssertEqual(FrequencyFormat.parse("14.0259"), 14_025_900)
        XCTAssertEqual(FrequencyFormat.parse("7074"), 7074)
        XCTAssertEqual(FrequencyFormat.parse("7074.5"), 7_074_500)
    }
}
