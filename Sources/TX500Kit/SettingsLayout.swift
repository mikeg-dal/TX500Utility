import Foundation

/// Decoded layout of the TX-500 settings table (`XL1000`…`XL2023`, `.set` files).
///
/// `builtInFields` is the baseline shipped with the app. Discoveries made on a radio (CAT matching,
/// Teach a Setting, CAT verification) are stored separately and merged on top with `merged(with:)`.
public enum SettingsLayout {
    private typealias L = TX500Protocol.Settings.Layout

    public static let builtInFields: [SettingsField] =
        withoutOverlaps(header + bandStack + discovered + filters + reserved)
            .sorted { $0.offset < $1.offset }

    /// Keeps the first field claiming each bit; later ones that would collide are dropped.
    ///
    /// Overlap is judged per *bit*, not per byte, because the radio packs several menu settings into
    /// one byte (menu 13's three CW key choices and CW weight all live in `0x276`). A field with no
    /// `bits` claims its whole byte, so an old whole-byte guess still blocks a later duplicate.
    private static func withoutOverlaps(_ fields: [SettingsField]) -> [SettingsField] {
        var claimed: [Int: Int] = [:]
        var kept: [SettingsField] = []
        for field in fields {
            guard !field.range.contains(where: { (claimed[$0] ?? 0) & field.bitMask != 0 }) else { continue }
            field.range.forEach { claimed[$0, default: 0] |= field.bitMask }
            kept.append(field)
        }
        return kept
    }

    /// Built-in fields with `userFields` layered on top. A user field replaces any built-in field it overlaps.
    public static func merged(with userFields: [SettingsField]) -> [SettingsField] {
        var occupied = IndexSet()
        userFields.forEach { occupied.insert(integersIn: $0.range) }
        let kept = builtInFields.filter { !occupied.intersects(integersIn: $0.range) }
        return (kept + userFields).sorted { $0.offset < $1.offset }
    }

    /// `fields` plus one-byte "undecoded" rows for every byte not covered by a field.
    public static func rows(for fields: [SettingsField], includeUndecoded: Bool) -> [SettingsField] {
        guard includeUndecoded else { return fields }
        var covered = IndexSet()
        fields.forEach { covered.insert(integersIn: $0.range) }
        let extra = (0..<TX500Protocol.Settings.byteCount).filter { !covered.contains($0) }.map {
            SettingsField(group: undecodedGroup, name: String(format: "Byte 0x%03X", $0), offset: $0, kind: .uint8, confidence: .unknown)
        }
        return (fields + extra).sorted { $0.offset < $1.offset }
    }

    public static func field(containing offset: Int, in fields: [SettingsField]) -> SettingsField? {
        fields.first { $0.range.contains(offset) }
    }

    /// Byte counts for the viewer's coverage line.
    public struct Coverage: Equatable, Sendable {
        public let confirmed: Int
        public let inferred: Int
        public let unknownDecoded: Int
        public let reserved: Int
        public let undecoded: Int
    }

    public static func coverage(of fields: [SettingsField]) -> Coverage {
        var sets: [String: IndexSet] = [:]
        for f in fields {
            let key = f.kind == .reserved ? reservedKey : f.confidence.rawValue
            sets[key, default: IndexSet()].insert(integersIn: f.range)
        }
        let covered = sets.values.reduce(IndexSet()) { $0.union($1) }
        return Coverage(confirmed: sets[FieldConfidence.confirmed.rawValue]?.count ?? 0,
                        inferred: sets[FieldConfidence.inferred.rawValue]?.count ?? 0,
                        unknownDecoded: sets[FieldConfidence.unknown.rawValue]?.count ?? 0,
                        reserved: sets[reservedKey]?.count ?? 0,
                        undecoded: TX500Protocol.Settings.byteCount - covered.count)
    }

    public static let undecodedGroup = "Undecoded"
    private static let reservedKey = "reserved"

    // MARK: Header

    private static let header: [SettingsField] = [
        SettingsField(group: "Header", name: "Signature", offset: L.signatureOffset, kind: .bytes, length: L.headerFieldLength,
                      confidence: .confirmed, note: "55 AA in every backup"),
        SettingsField(group: "Header", name: "Format marker", offset: L.formatMarkerOffset, kind: .bytes, length: L.headerFieldLength,
                      confidence: .inferred, note: "78 AE in every backup so far, even when contents differ — not a checksum"),
    ]

    // MARK: Band stack (per-band VFO memory)

    private static let bandStack: [SettingsField] = L.bandRecordNames.enumerated().flatMap { index, name in
        let base = L.bandRecordStart + index * L.bandRecordSize
        let group = index >= L.currentVFORecordIndex ? "Current VFO" : "Band Stack"
        return [
            SettingsField(group: group, name: "\(name) frequency", offset: base, kind: .frequencyHz, confidence: .inferred,
                          note: "Values are band edges (1.8, 3.5, 7 MHz…) and follow tuning"),
            // Byte 4 holds the mode in its low three bits and the filter preset in bits 5-6. In a
            // backup the low bands read 3 (CW) and the high bands 2 (USB), which are the radio's
            // own band defaults, and the codes match the CAT MD table.
            SettingsField(group: group, name: "\(name) mode", offset: base + L.bandModeOffset, kind: .uint8,
                          confidence: .confirmed, note: "Low three bits, using the same codes as CAT MD",
                          bits: 0...2, values: [0: "—", 1: "LSB", 2: "USB", 3: "CW", 4: "FM", 5: "AM", 6: "DIG", 7: "CW-R"]),
            SettingsField(group: group, name: "\(name) filter preset", offset: base + L.bandModeOffset, kind: .uint8,
                          confidence: .confirmed,
                          note: "Pressing FILTER moved bits 5-6 of this byte, so the preset is remembered per band record",
                          bits: 5...6, values: [0: "FIL1", 1: "FIL2", 2: "FIL3", 3: "FIL4"]),
            SettingsField(group: group, name: "\(name) extra", offset: base + L.bandModeOffset + 1, kind: .bytes,
                          length: L.amFMEnabledOffset - L.bandModeOffset - 1, confidence: .unknown),
            // Byte 6 of each record is per-band flags: menu 18 and the preamp/attenuator setting
            // both write into the record of the band you are on, so every band keeps its own copy.
            SettingsField(group: group, name: "\(name) RF front end", offset: base + L.amFMEnabledOffset,
                          kind: .uint8, confidence: .inferred,
                          note: "CAT PA moved bit 2 and CAT RA moved bits 2-3, so these are one two-bit setting rather than two switches. Which code means which is not yet checked",
                          bits: 2...3),
            SettingsField(group: group, name: "\(name) RIT on", offset: base + L.amFMEnabledOffset,
                          kind: .uint8, confidence: .confirmed,
                          note: "CAT RT moved bit 4 of this byte, so RIT state is remembered per band",
                          bits: 4...4, values: [0: "Off", 1: "On"]),
            SettingsField(group: group, name: "\(name) XIT on", offset: base + L.amFMEnabledOffset,
                          kind: .uint8, confidence: .confirmed,
                          note: "CAT XT moved bit 5 of this byte, so XIT state is remembered per band",
                          bits: 5...5, values: [0: "Off", 1: "On"]),
            SettingsField(group: group, name: "\(name) AM/FM enabled", offset: base + L.amFMEnabledOffset,
                          kind: .uint8, confidence: .confirmed,
                          note: "Menu 18 moved bit 6 of this byte in the VFO A record (0x20A) on firmware 1.30.00",
                          bits: 6...6, values: [0: "Off", 1: "On"]),
            SettingsField(group: group, name: "\(name) extra 2", offset: base + L.amFMEnabledOffset + 1, kind: .bytes,
                          length: L.ritOffsetOffset - L.amFMEnabledOffset - 1, confidence: .unknown),
            SettingsField(group: group, name: "\(name) RIT/XIT offset", offset: base + L.ritOffsetOffset,
                          kind: .uint16, confidence: .confirmed,
                          note: "Signed 16-bit, in Hz, checked against the display: the radio read -4000 and the bytes read 61536. CLR takes it to 0. RIT and XIT share one offset, as the CAT IF frame does",
                          unit: "Hz", signed: true),
            SettingsField(group: group, name: "\(name) extra 3", offset: base + L.ritOffsetOffset + 2, kind: .bytes,
                          length: L.bandRecordSize - L.ritOffsetOffset - 2, confidence: .unknown),
        ]
    }

    // MARK: Filters

    private static let filters: [SettingsField] = {
        var out: [SettingsField] = []
        for table in FilterTable.Table.allCases {
            for (preset, offset) in table.offsets.enumerated() {
                out.append(SettingsField(group: "Filters", name: "\(table.label) FIL\(preset + 1)", offset: offset,
                                         kind: .uint16, confidence: table.confidence, unit: "Hz"))
            }
        }
        let txNames = ["TX SSB low cut", "TX SSB high cut", "TX AM width", "TX FM width"]
        for (i, name) in txNames.enumerated() {
            for preset in 0..<L.txFilterPresetCount {
                out.append(SettingsField(group: "Filters", name: "\(name) FIL\(preset + 1)",
                                         offset: L.txFilterStart + (i * L.txFilterPresetCount + preset) * MemoryLayout<UInt16>.size,
                                         kind: .uint16, confidence: .inferred, note: "Two TX presets per mode (CAT FL P2 is 0–1)", unit: "Hz"))
            }
        }
        return out
    }()

    // MARK: Confirmed on hardware (firmware 1.30.00)

    /// Every entry here was verified on a radio: the setting was changed and this byte moved with it
    /// (menu pass via tools/discover.py, plus CAT verification for the ones with a CAT command).
    /// This table *is* the offset map — the numbers are protocol data, not magic constants.
    private static let discovered: [SettingsField] = [
        // 0x224-0x227 pack several menu settings into each byte. The bit for each was found by
        // recording which bits flipped when that one setting changed (tools/discover.py, and
        // tools/MAPPING.md for the full table).
        field("Tuning", "Step size", 0x224, .uint8, bits: 0...1,
              note: "Changing the VFO tuning step moved bits 0-1; two bits, so at most four step sizes"),
        field("Display", "22 TX meter", 0x224, .uint8, bits: 4...4, confidence: .inferred,
              note: "Menu 22 moved bit 4, but the meter has four settings (POWER/SWR/MIC-DIG/ALC) which need two bits, so this is probably half of a wider field. CAT RM changes the meter without touching the table at all"),
        field("Audio", "Monitor", 0x224, .uint8, bits: 7...7, values: [0: "Off", 1: "On"],
              note: "Found automatically by flipping CAT MO and watching which bit moved"),
        field("DSP", "16 Notch filter type", 0x225, .uint8, bits: 5...5),
        field("Tuning", "25 Encoder mode", 0x225, .uint8, bits: 3...3),
        field("VFO", "Split", 0x225, .uint8, bits: 0...0, values: [0: "Off", 1: "On"],
              note: "Found automatically by flipping CAT SP and watching which bit moved"),
        field("VFO", "Lock", 0x225, .uint8, bits: 4...4, values: [0: "Off", 1: "On"],
              note: "Found automatically by flipping CAT LK and watching which bit moved"),
        field("DSP", "Notch", 0x226, .uint8, bits: 0...0, values: [0: "Off", 1: "On"]),
        field("DSP", "Noise reduction", 0x226, .uint8, bits: 1...1, values: [0: "Off", 1: "On"]),
        field("DSP", "Noise blanker", 0x226, .uint8, bits: 2...2, values: [0: "Off", 1: "On"]),
        field("Band", "21 Save band VFO", 0x226, .uint8, bits: 4...4, values: [0: "Off", 1: "On"]),
        field("DSP", "DSP IF set", 0x226, .uint8, bits: 5...5, values: [0: "Off", 1: "On"]),
        field("TX", "19 Tone type", 0x226, .uint8, bits: 6...6),
        field("TX", "Speech compressor", 0x226, .uint8, bits: 7...7, values: [0: "Off", 1: "On"],
              note: "CAT PR moves bit 7. An early test called this whole byte the compressor and the menu pass called it Save band VFO — both were right about their own bit"),
        field("CW", "14 CW decode RX", 0x227, .uint8, bits: 6...6, values: [0: "Off", 1: "On"]),
        field("CW", "14 CW decode TX", 0x227, .uint8, bits: 7...7, values: [0: "Off", 1: "On"]),
        field("Display", "31 Backlight", 0x227, .uint8, bits: 2...2),
        field("Audio", "33 Audio out", 0x227, .uint8, bits: 5...5),
        field("CW", "10 CW pitch", 0x260, .uint16, unit: "Hz"),
        field("CW", "11 CW speed", 0x262, .uint16, unit: "CPM"),
        field("VOX", "09 VOX delay MIC", 0x264, .uint16, unit: "ms"),
        field("VOX", "09 VOX delay CW", 0x266, .uint16, unit: "ms"),
        field("VOX", "08 VOX level MIC", 0x268, .uint8),
        field("EQ", "17 EQ RX LF", 0x269, .uint8),
        field("EQ", "17 EQ RX MF", 0x26A, .uint8),
        field("EQ", "17 EQ RX HF", 0x26B, .uint8),
        field("EQ", "17 EQ TX LF", 0x26C, .uint8),
        field("EQ", "17 EQ TX MF", 0x26D, .uint8,
              note: "Measured on the radio, and a factory-reset 1.30 radio both stores and displays 100. The manual covers FW 1.2 and lists different TX EQ defaults, so where the two disagree the radio is right"),
        field("EQ", "17 EQ TX HF", 0x26E, .uint8),
        field("Gain", "03 Gain MIC", 0x272, .uint8),
        field("Gain", "03 Gain DIG", 0x273, .uint8),
        field("TX", "04 CMR level (compressor)", 0x274, .uint8),
        field("TX", "00 Power", 0x275, .uint8, unit: "%"),
        // One byte, four settings. The weight values were read off the radio while stepping it from
        // end to end: raw 0-5 showed 2:1, 2.5:1, 3:1, 3.5:1, 4:1, 4.5:1.
        field("CW", "12 CW weight", 0x276, .uint8, bits: 0...2,
              values: [0: "2:1", 1: "2.5:1", 2: "3:1", 3: "3.5:1", 4: "4:1", 5: "4.5:1"]),
        field("CW", "13 CW key AUTO", 0x276, .uint8, bits: 4...4, values: [0: "Iambic A", 1: "Iambic B"]),
        field("CW", "13 CW key REV", 0x276, .uint8, bits: 5...5, values: [0: "Disabled", 1: "Enabled"]),
        field("CW", "13 CW key TYPE", 0x276, .uint8, bits: 6...6, values: [0: "Single", 1: "Auto"]),
        field("AGC", "01 AGC CW", 0x277, .uint8),
        field("AGC", "01 AGC SSB", 0x278, .uint8),
        field("AGC", "01 AGC AM", 0x279, .uint8),
        field("RF", "02 RF gain CW", 0x27A, .uint8, unit: "dB", scale: -1, displayOffset: 5,
              note: "The table stores RF gain inverted: the displayed dB is 5 minus the byte, checked on a factory radio which showed -1 dB with 6 stored, and 0 dB in the other four modes with 5 stored. This is a different scale from CAT RG, where 92 reads as 0 dB"),
        field("RF", "02 RF gain SSB", 0x27B, .uint8, unit: "dB", scale: -1, displayOffset: 5,
              note: "The table stores RF gain inverted: the displayed dB is 5 minus the byte, checked on a factory radio which showed -1 dB with 6 stored, and 0 dB in the other four modes with 5 stored. This is a different scale from CAT RG, where 92 reads as 0 dB"),
        field("RF", "02 RF gain DIG", 0x27C, .uint8, unit: "dB", scale: -1, displayOffset: 5,
              note: "The table stores RF gain inverted: the displayed dB is 5 minus the byte, checked on a factory radio which showed -1 dB with 6 stored, and 0 dB in the other four modes with 5 stored. This is a different scale from CAT RG, where 92 reads as 0 dB"),
        field("RF", "02 RF gain AM", 0x27D, .uint8, unit: "dB", scale: -1, displayOffset: 5,
              note: "The table stores RF gain inverted: the displayed dB is 5 minus the byte, checked on a factory radio which showed -1 dB with 6 stored, and 0 dB in the other four modes with 5 stored. This is a different scale from CAT RG, where 92 reads as 0 dB"),
        field("RF", "02 RF gain FM", 0x27E, .uint8, unit: "dB", scale: -1, displayOffset: 5,
              note: "The table stores RF gain inverted: the displayed dB is 5 minus the byte, checked on a factory radio which showed -1 dB with 6 stored, and 0 dB in the other four modes with 5 stored. This is a different scale from CAT RG, where 92 reads as 0 dB"),
        field("Squelch", "07 SQL SSB/AM", 0x27F, .uint8),
        field("Squelch", "07 SQL FM", 0x280, .uint8),
        field("DSP", "05 NR level", 0x281, .uint8, displayOffset: -1,
              note: "The byte is confirmed; its scale is not. A factory-reset radio displays 50 while this byte holds 51, so the shown value looks like the byte minus one. Observed once — needs a second reading at a different value before relying on it"),
        field("DSP", "06 NB level", 0x282, .uint8),
        field("DSP", "Notch filter width (CAT AL)", 0x283, .uint8, bits: 0...0,
              note: "CAT AL moves bit 0. Menu 16's notch type is 0x225 bit 5, so this is a second, separate notch control; the radio does not answer CAT NF at all"),
        field("Panadapter", "24 TX pan scale", 0x284, .uint8, scale: 0.1),
        field("Panadapter", "24 TX pan shift", 0x285, .uint8, signed: true),
        field("Panadapter", "24 TX pan average", 0x286, .uint8),
        field("Panadapter", "23 RX pan scale", 0x287, .uint8, scale: 0.1),
        field("Panadapter", "23 RX pan shift", 0x288, .uint8, signed: true),
        field("Panadapter", "23 RX pan average", 0x289, .uint8),
        field("Display", "Last menu item shown", 0x28A, .uint8,
              note: "Menu cursor, not a setting: read 13 then 26 after stepping from menu 13 to menu 26"),
        field("Audio", "AF gain", 0x28C, .uint8),
        field("Audio", "Monitor level", 0x28F, .uint8),
        field("CW", "CW memory flag", 0x28E, .uint8, bits: 2...2,
              note: "Editing a CW keyer message moved this bit. One bit cannot hold message text, so the messages live elsewhere and this is a flag about them — what exactly it means is not yet known"),
        field("Clock", "30 Clock correction", 0x290, .uint8, signed: true,
              note: "Menu 30 CORR TIME. The clock itself is not in this table: nothing moved anywhere in 1024 bytes over three minutes of watching"),
        field("VOX", "09 VOX delay DIG", 0x292, .uint16, unit: "ms"),
        field("VOX", "08 VOX level DIG", 0x294, .uint8),
        field("Display", "32 Contrast", 0x295, .uint8),
        field("CW", "15 Beacon interval CW", 0x296, .uint8, unit: "s",
              note: "Only this byte moved; 0x297 is unclaimed, so it may yet prove 16-bit"),
        field("CW", "15 Beacon interval MIC", 0x298, .uint8, unit: "s",
              note: "Only this byte moved; 0x299 is unclaimed, so it may yet prove 16-bit"),
        field("Tuning", "20 Freq ref correction", 0x29A, .uint8, unit: "Hz", signed: true,
              note: "Only this byte moved; 0x29B is unclaimed, so it may yet prove 16-bit"),
        // Another packed byte: four menu settings share it.
        field("Tuning", "26 Alt encoder", 0x29C, .uint8, bits: 1...2),
        field("Memory", "27 Select memory", 0x29C, .uint8, bits: 3...3),
        field("CAT", "35 CAT protocol", 0x29C, .uint8, bits: 4...4, values: [0: "TS-2000", 1: "LAB599"],
              confidence: .inferred, note: "Bit confirmed by changing menu 35; which value means which mode is not yet checked"),
        field("Audio", "34 Audio in", 0x29C, .uint8, bits: 7...7),
        field("TX", "19 Tone PWR (tune level)", 0x2A4, .uint8, unit: "%"),
    ]

    private static func field(_ group: String, _ name: String, _ offset: Int, _ kind: SettingsField.Kind,
                              unit: String = "", scale: Double = 1, signed: Bool = false,
                              bits: ClosedRange<Int>? = nil, values: [Int: String]? = nil,
                              displayOffset: Double = 0,
                              confidence: FieldConfidence = .confirmed, note: String? = nil) -> SettingsField {
        SettingsField(group: group, name: name, offset: offset, kind: kind, confidence: confidence,
                      note: note ?? defaultNote(bits: bits),
                      scale: scale, unit: unit, signed: signed, bits: bits, values: values,
                      displayOffset: displayOffset)
    }

    private static func defaultNote(bits: ClosedRange<Int>?) -> String {
        let verified = "Verified on firmware 1.30.00 by changing this setting and watching the byte"
        guard let bits else { return verified }
        let which = bits.count == 1 ? "bit \(bits.lowerBound)" : "bits \(bits.lowerBound)-\(bits.upperBound)"
        return verified + ", which moved only \(which) — this byte holds several menu settings"
    }

    // MARK: CW

    private static let keyer: [SettingsField] = []

    // MARK: Reserved

    private static let reserved: [SettingsField] = [
        SettingsField(group: "Reserved", name: "Unused area", offset: L.reservedStart, kind: .reserved,
                      length: TX500Protocol.Settings.byteCount - L.reservedStart, confidence: .inferred,
                      note: "Zero in normal use, but not reserved for certain: a backup taken straight after a factory reset had 0x2B1 = 161, and every other backup has it at zero. Something writes there during a reset and ordinary operation clears it"),
    ]
}
