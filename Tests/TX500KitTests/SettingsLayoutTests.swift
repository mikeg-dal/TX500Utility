import XCTest
@testable import TX500Kit

/// Decodes a real backup taken from the test radio on 2026-09-15.
final class SettingsLayoutTests: XCTestCase {
    func loadFixture() throws -> SettingsBackup {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "radio-2026-09-15", withExtension: "set", subdirectory: "Fixtures"))
        return try SettingsBackup(fileData: Data(contentsOf: url))
    }

    func field(_ name: String) throws -> SettingsField {
        try XCTUnwrap(SettingsLayout.builtInFields.first { $0.name == name }, name)
    }

    func testBandStackAndCurrentVFO() throws {
        let bytes = try loadFixture().bytes
        XCTAssertEqual(try field("Signature").hex(in: bytes), "55 AA")
        XCTAssertEqual(try field("Format marker").formattedValue(in: bytes), "78 AE")
        XCTAssertEqual(try field("11 CW speed").rawValue(in: bytes), 100)  // fixture taken before the 60 CPM change
        XCTAssertEqual(try field("160m A frequency").rawValue(in: bytes), 1_800_000)
        XCTAssertEqual(try field("6m A frequency").rawValue(in: bytes), 50_000_000)
        XCTAssertEqual(try field("GEN A frequency").rawValue(in: bytes), 500_000)
        XCTAssertEqual(try field("VFO B frequency").rawValue(in: bytes), 10_100_000)
        XCTAssertEqual(try field("VFO B frequency").formattedValue(in: bytes), "10.100.000 MHz")
        XCTAssertEqual(try field("23 RX pan scale").formattedValue(in: bytes), "0.9")
        XCTAssertEqual(try field("09 VOX delay CW").formattedValue(in: bytes), "400 ms")
        XCTAssertEqual(try field("03 Gain MIC").rawValue(in: bytes), 25)
        XCTAssertEqual(try field("TX SSB high cut FIL1").formattedValue(in: bytes), "3250 Hz")
        XCTAssertEqual(try field("Unused area").formattedValue(in: bytes), "all zero (344 bytes)")
    }

    func testFilterTable() throws {
        let table = FilterTable(bytes: try loadFixture().bytes)
        XCTAssertEqual(table.bandwidth(mode: .usb, preset: 0), 3_000)   // 250–3250
        XCTAssertEqual(table.bandwidth(mode: .lsb, preset: 3), 2_050)   // 350–2400
        XCTAssertEqual(table.bandwidth(mode: .cw, preset: 0), 300)
        XCTAssertEqual(table.bandwidth(mode: .am, preset: 0), 10_000)
        XCTAssertNil(table.bandwidth(mode: .dig, preset: 0))
        XCTAssertNil(table.bandwidth(mode: .usb, preset: 4))
        XCTAssertEqual(FilterTable.format(3_000), "3.0 k")
        XCTAssertEqual(FilterTable.format(300), "300 Hz")
    }

    func testRowsCoverEveryByteWhenUndecodedIncluded() {
        var covered = IndexSet()
        SettingsLayout.rows(for: SettingsLayout.builtInFields, includeUndecoded: true).forEach { covered.insert(integersIn: $0.range) }
        XCTAssertEqual(covered.count, TX500Protocol.Settings.byteCount)
    }

    func testHardwareVerifiedFieldsReadCorrectly() throws {
        let bytes = try loadFixture().bytes
        // Values on the test radio when this fixture was captured.
        XCTAssertEqual(try field("01 AGC CW").rawValue(in: bytes), 3)
        XCTAssertEqual(try field("02 RF gain SSB").rawValue(in: bytes), 5)
        XCTAssertEqual(try field("07 SQL SSB/AM").rawValue(in: bytes), 0)
        XCTAssertEqual(try field("00 Power").formattedValue(in: bytes), "10 %")
        XCTAssertEqual(try field("24 TX pan scale").formattedValue(in: bytes), "2.7")
        XCTAssertEqual(try field("23 RX pan shift").integerValue(in: bytes), 30)
        XCTAssertEqual(try field("10 CW pitch").formattedValue(in: bytes), "500 Hz")
        XCTAssertEqual(try field("17 EQ RX MF").rawValue(in: bytes), 75)
    }

    /// `tools/map.json` is where the Python discovery runs record what they measured on the radio;
    /// `SettingsLayout.discovered` is what the app ships. They are kept in step by hand, so this
    /// guards the copy: every field the tools call *confirmed* must exist here, at the same offset,
    /// the same width, and confirmed here too.
    ///
    /// Matching is by offset, not name — the app's names carry extra wording ("04 CMR level
    /// (compressor)") while the map uses the bare menu labels its prompts are keyed on.
    /// Refresh the fixture with `cp tools/map.json Tests/TX500KitTests/Fixtures/map.json`.
    func testMapJSONMatchesLayout() throws {
        struct MappedField: Decodable {
            let name: String
            let offset: Int
            let length: Int?
            let confidence: String?
        }
        struct Map: Decodable { let fields: [String: MappedField] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "map", withExtension: "json", subdirectory: "Fixtures"))
        let mapped = try JSONDecoder().decode(Map.self, from: Data(contentsOf: url))
        let confirmed = mapped.fields.values.filter { $0.confidence == "confirmed" }
        XCTAssertGreaterThan(confirmed.count, 20, "fixture looks empty — did the copy go wrong?")

        for field in confirmed {
            // A byte can hold several settings, so look at every field at this offset and require
            // that at least one of them is the confirmed field of the right width.
            let atOffset = SettingsLayout.builtInFields.filter { $0.offset == field.offset }
            guard !atOffset.isEmpty else {
                XCTFail("\(field.name) (\(hex(field.offset))) is confirmed in map.json but missing from SettingsLayout")
                continue
            }
            XCTAssertTrue(atOffset.contains { $0.length == field.length ?? 1 && $0.confidence == .confirmed },
                          "\(field.name) (\(hex(field.offset))) is confirmed in map.json, but SettingsLayout has "
                          + atOffset.map { "\($0.name) [\($0.length)B \($0.confidence.rawValue)]" }.joined(separator: ", "))
        }
    }

    private func hex(_ offset: Int) -> String { "0x" + String(offset, radix: 16, uppercase: true) }

    /// The same radio, backed up twice within minutes: once by this app and once by Lab599's own
    /// Windows TRXSettings tool. The two files are byte-for-byte identical, which is the strongest
    /// check we have that the `XL` read path is right — addressing, batching and framing all agree
    /// with the vendor's independent implementation.
    ///
    /// Keep both fixtures. They also pin the `.set` format: our files are interchangeable with the
    /// vendor tool's in both directions.
    func testOurBackupMatchesTheVendorToolByteForByte() throws {
        func fixture(_ name: String) throws -> [UInt8] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "set", subdirectory: "Fixtures"))
            return [UInt8](try Data(contentsOf: url))
        }
        let ours = try fixture("ours-2026-09-16")
        let vendor = try fixture("vendor-2026-09-16")
        XCTAssertEqual(ours.count, TX500Protocol.Settings.byteCount)
        XCTAssertEqual(Array(ours.prefix(2)), TX500Protocol.Settings.signature)
        let differing = ours.indices.filter { ours[$0] != vendor[$0] }
        XCTAssertTrue(differing.isEmpty,
                      "differs from the vendor tool at " + differing.map { String(format: "0x%03X", $0) }.joined(separator: ", "))
    }

    /// Some settings are stored on a different scale from the one the radio shows. Checked against a
    /// factory-reset radio on firmware 1.30, reading the values off its own display.
    func testStoredValuesAreShownOnTheRadiosScale() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ours-2026-09-16", withExtension: "set", subdirectory: "Fixtures"))
        var bytes = [UInt8](try Data(contentsOf: url))
        // RF gain counts down from +5 dB: the radio displayed -1 dB while this byte held 6.
        bytes[0x27A] = 6
        XCTAssertEqual(try field("02 RF gain CW").formattedValue(in: bytes), "-1 dB")
        bytes[0x27A] = 5
        XCTAssertEqual(try field("02 RF gain CW").formattedValue(in: bytes), "0 dB")
        bytes[0x27A] = 0
        XCTAssertEqual(try field("02 RF gain CW").formattedValue(in: bytes), "5 dB", "byte 0 is maximum gain")
        // NR level reads one lower than it stores: the radio showed 50 with 51 stored.
        bytes[0x281] = 51
        XCTAssertEqual(try field("05 NR level").formattedValue(in: bytes), "50")
        // MIC gain needs no conversion: the radio showed 25 with 25 stored.
        bytes[0x272] = 25
        XCTAssertEqual(try field("03 Gain MIC").formattedValue(in: bytes), "25")
    }

    /// Two fields may share a byte when the radio packs settings into separate bits of it, but they
    /// must not claim the same bits, and a field without `bits` claims the whole byte.
    func testFieldsDoNotOverlap() {
        var claimed: [Int: Int] = [:]      // byte offset → bits already spoken for
        for field in SettingsLayout.builtInFields {
            for offset in field.range {
                let taken = claimed[offset] ?? 0
                XCTAssertEqual(taken & field.bitMask, 0,
                               "\(field.name) claims bits already used at \(String(format: "0x%03X", offset))")
                claimed[offset] = taken | field.bitMask
            }
        }
    }

    func testPackedByteDecodesEachSettingSeparately() throws {
        var bytes = [UInt8](repeating: 0, count: TX500Protocol.Settings.byteCount)
        // 0x276 as read from the radio: weight 3 (3.5:1), AUTO set (Iambic B), REV clear, TYPE set.
        bytes[0x276] = 0b0101_0011
        XCTAssertEqual(try field("12 CW weight").formattedValue(in: bytes), "3.5:1")
        XCTAssertEqual(try field("13 CW key AUTO").formattedValue(in: bytes), "Iambic B")
        XCTAssertEqual(try field("13 CW key REV").formattedValue(in: bytes), "Disabled")
        XCTAssertEqual(try field("13 CW key TYPE").formattedValue(in: bytes), "Auto")
        // The six weight values the radio showed while stepping from one end to the other.
        let weight = try field("12 CW weight")
        let shown = (0...5).map { raw -> String in
            bytes[0x276] = UInt8(raw)
            return weight.formattedValue(in: bytes)
        }
        XCTAssertEqual(shown, ["2:1", "2.5:1", "3:1", "3.5:1", "4:1", "4.5:1"])
    }

    func testVoltageAndExtensionState() async throws {
        let responses = [
            "IF;": "IF00014025900     +000000000030000000;", "VL;": "VL14.2 ;", "GT;": "GT003;", "FL;": "FL21;",
            "MO;": "MO1;", "PR;": "PR1;", "PA;": "PA10;", "RA;": "RA0000;", "NT;": "NT0;", "LK;": "LK10;",
        ]
        let s = try await KenwoodCAT(transport: MockTransport(responses: responses)).readState()
        XCTAssertEqual(s.supplyVolts, 14.2)
        XCTAssertEqual(s.agcTimeConstant, 3)
        XCTAssertEqual(s.rxFilterPreset, 2)
        XCTAssertEqual(s.txFilterPreset, 1)
        // MO1 is muted, so the monitor is off. MO0 switches it on — confirmed on the radio.
        XCTAssertEqual(s.monitorOn, false)
        XCTAssertEqual(s.compressorOn, true)
        XCTAssertEqual(s.preampOn, true)
        XCTAssertEqual(s.attenuatorOn, false)
        XCTAssertEqual(s.locked, true)
    }
}
