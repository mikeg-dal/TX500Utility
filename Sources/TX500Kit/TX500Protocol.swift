import Foundation

/// Every protocol constant in one place. Values come from the TX-500 manual, the vendor
/// PureBasic tools (disassembled), and captures from a live radio.
public enum TX500Protocol {

    // MARK: Serial link

    public enum USB {
        public static let ftdiVendorID = 0x0403
        public static let prolificVendorID = 0x067B
    }

    // MARK: CAT (Kenwood-compatible ASCII)

    public enum CAT {
        /// The TX-500's CAT port runs at 9600 8-N-1 and has no speed setting of its own — the manual
        /// states it, and a full pass over menus 00-35 found nothing to change it.
        public static let baudRate = 9600
        /// Offered in Preferences for the unusual case of a serial bridge or adapter in between.
        /// Anything other than `baudRate` will stop the radio answering.
        public static let standardBaudRates = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400]

        /// A stored preference narrowed to a rate we offer, so a stray or stale value cannot leave
        /// the app unable to open the port. Anything unrecognised falls back to the radio's own rate.
        public static func supportedBaudRate(_ stored: Int) -> Int {
            standardBaudRates.contains(stored) ? stored : baudRate
        }
        public static let terminator: UInt8 = UInt8(ascii: ";")
        public static let terminatorString = ";"
        public static let commandPrefixLength = 2

        /// Normal wait for a get-command answer.
        public static let responseTimeout: TimeInterval = 0.5
        /// Shorter wait used when probing commands that may not exist.
        public static let probeTimeout: TimeInterval = 0.3
        /// Pause after a set command before the next query.
        public static let postSetDelay: TimeInterval = 0.05

        /// `ID;` answers per CAT protocol setting on the radio (Lab599 CAT Protocol rev. 2).
        public enum Identity: String, Sendable, CaseIterable {
            case ts2000 = "ID019;"
            case lab599 = "ID500;"
            case lab599MP = "ID505;"

            public var label: String {
                switch self {
                case .ts2000: "TS-2000 mode"
                case .lab599: "LAB599 mode"
                case .lab599MP: "LAB599 mode (TX-500MP)"
                }
            }
        }

        public static let frequencyDigits = 11
        public static let frequencyRangeHz = 30_000...99_999_999_999
        /// Front-panel scales, calibrated against a live radio (2026-09-15) by sweeping each control
        /// on the radio and logging the raw CAT value.
        public enum Levels {
            /// `PC` raw 010…100 is the radio's output power in percent.
            public static let powerPercent = LevelScale(rawRange: 10...100, displayRange: 10...100, unit: "%")
            /// `AG0` raw 000…250 ↔ radio AF gain 0…100.
            public static let afGain = LevelScale(rawRange: 0...250, displayRange: 0...100, unit: "")
            /// `RG` raw 000…100 ↔ radio RF gain −51…+5 dB (raw 92 = 0 dB, so the radio rounds down).
            /// Stored per mode by the radio; CAT reports the current mode's value.
            public static let rfGain = LevelScale(rawRange: 0...100, displayRange: -51...5, unit: "dB", rounding: .down)
            /// `KS` raw 010…300 is the keyer speed in characters per minute.
            public static let keyerSpeed = LevelScale(rawRange: 10...300, displayRange: 10...300, unit: "CPM")
            /// Step used by the app's power control.
            public static let powerStep = 5
        }
        /// `FL` RX filter presets (FIL1–FIL4 on the radio).
        public static let rxFilterPresetCount = 4
        /// `GT` AGC time constant range.
        public static let agcRange = 1...10
        /// `PT;` → `PT0;` receive, `PT1;` transmit.
        public static let pttStatusCommand = "PT"
        public static let receiveCommand = "RX"
        /// `VL` answer, e.g. `VL14.2 ;` — volts as text.
        public static let voltageCommand = "VL"
        /// Kenwood `SM0` full-scale reading (S9+60 dB). Assumed for the TX-500; verify on air.
        public static let sMeterFullScale = 30
        public static let threeDigitField = "%03d"

        /// `IF;` body layout (35 chars between `IF` and `;`).
        public enum InformationFrame {
            public static let bodyLength = 35
            public static let frequency = 0..<11
            public static let ritOffset = 16..<21
            public static let ritOn = 21
            public static let xitOn = 22
            public static let memoryChannel = 23..<26
            public static let transmitting = 26
            public static let mode = 27
            public static let vfo = 28
            public static let scan = 29
            public static let split = 30
        }

        /// Live-view polling cadence.
        public static let livePollInterval: Duration = .milliseconds(200)
        /// Full-state refresh (gains, power, etc.) every N live polls.
        public static let fullRefreshEveryPolls = 10
    }

    // MARK: Bands (for the mode & band survey; receive-only tuning)

    public struct Band: Sendable, Hashable, Identifiable {
        public var id: String { name }
        public let name: String
        public let frequencyHz: Int
    }

    /// One frequency per band-stack entry, matching the radio's band records.
    public static let bands: [Band] = [
        Band(name: "160m", frequencyHz: 1_850_000), Band(name: "80m", frequencyHz: 3_600_000),
        Band(name: "60m", frequencyHz: 5_350_000), Band(name: "40m", frequencyHz: 7_100_000),
        Band(name: "30m", frequencyHz: 10_120_000), Band(name: "20m", frequencyHz: 14_100_000),
        Band(name: "17m", frequencyHz: 18_100_000), Band(name: "15m", frequencyHz: 21_100_000),
        Band(name: "12m", frequencyHz: 24_920_000), Band(name: "11m", frequencyHz: 27_000_000),
        Band(name: "10m", frequencyHz: 28_500_000), Band(name: "6m", frequencyHz: 50_100_000),
        Band(name: "GEN", frequencyHz: 9_500_000),
    ]

    /// AM and FM are enabled per band (menu 18) and are off by default below 29 MHz, so a mode the radio
    /// refuses is retried on 6 m, which is safely above that limit.
    public static let amFMFallbackBand = Band(name: "6m", frequencyHz: 50_100_000)

    // MARK: Firmware bootloader

    public enum Bootloader {
        public static let baudRate = 57_600
        public static let headerLength = 16
        public static let magic = Data("BL20".utf8)
        public static let acknowledgement = Data("OK".utf8)
        /// Vendor tool polls in 1 ms steps up to 5000 iterations.
        public static let answerTimeout: TimeInterval = 5.0
        /// Vendor tool waits 100 ms after opening before flushing input.
        public static let settleDelay: TimeInterval = 0.1
        /// Payload write size; the loader has no per-block ACK, so this only affects progress granularity.
        public static let chunkSize = 64
        /// Sanity bounds for `.fw` images (1.30.00 is 246,384 bytes).
        public static let imageSizeRange = 1_024...4_194_304
    }

    // MARK: Settings backup (XL read / XS write) — from Lab599 TRXSettings 1.0

    public enum Settings {
        /// `XL<address>;` → `XLnnn;` (value in decimal).
        public static let readCommand = "XL"
        /// `XS<address> <value>;` → 4-byte reply (content not checked by the vendor tool).
        public static let writeCommand = "XS"
        public static let writeSeparator = " "
        public static let firstAddress = 1000
        public static let byteCount = 1024
        public static let valueDigits = 3
        public static let writeReplyLength = 4
        public static let replyTimeout: TimeInterval = 0.5
        /// Sent after a batch of `XL` reads to mark where our answers end — `XL` answers carry no
        /// address, so without it a stale answer would shift the whole batch unnoticed.
        public static let sentinelCommand = "ID;"
        public static let sentinelPrefix = "ID"
        /// Every settings table starts with these two bytes; a full read that doesn't is misaligned.
        public static let signature: [UInt8] = [0x55, 0xAA]
        /// `XL` requests sent per write. Measured on the radio: 1 → 51 s, 16 → 11 s, 32 → 9.5 s for all 1024
        /// bytes, identical results. 16 leaves room for live polling between batches.
        public static let readBatchSize = 16
        /// Pause after a CAT set during a sweep before reading the settings table.
        public static let sweepSettleDelay: TimeInterval = 0.3
        /// Pause after changing mode or frequency during a survey before reading.
        public static let surveySettleDelay: TimeInterval = 0.5
        /// CAT settings the manual (FW v1.2) says are stored per mode.
        public static let perModeProbeCommands = ["RG", "GT", "SQ0", "VG", "VD"]
        /// Band stack and current-VFO records: expected to change with mode/band, excluded from "dependent bytes".
        public static let vfoRecordArea = Layout.bandRecordStart..<Layout.menuAreaStart
        /// Multiples of a probe's step tried when picking test values that don't collide with other probes.
        public static let locatorStepMultiples = [1, 2, 3, 4, 5, 6, 7, 8]
        /// Allowed difference (in displayed units) when matching a display-encoded byte during a sweep.
        public static let displayMatchTolerance = 1
        /// How long to wait for an optional `XS` reply before verifying with `XL`.
        public static let optionalReplyWait: TimeInterval = 0.1
        /// `.set` files are the 1024 raw bytes in address order.
        public static let fileExtension = "set"

        /// Byte offsets inside the table, decoded from a live backup (see `SettingsLayout`).
        public enum Layout {
            public static let signatureOffset = 0x000
            public static let formatMarkerOffset = 0x002
            public static let headerFieldLength = 2
            /// UInt16 LE, characters per minute (same value as CAT `KS`).
            public static let keyerSpeedOffset = 0x262
            public static let bandRecordStart = 0x004
            public static let bandRecordSize = 16
            /// Offset of the mode/flags byte inside a band record (after the UInt32 frequency).
            public static let bandModeOffset = 4
            /// Byte inside a band record whose bit 6 is menu 18 AM/FM enabled — stored per band,
            /// not once globally (measured at 0x20A, byte 6 of the VFO A record).
            public static let amFMEnabledOffset = 6
            /// Bytes inside a band record holding the RIT/XIT offset in Hz: CLR took 0x20C from
            /// 200 to 0. Recorded as one byte because that is all that moved; the protocol allows
            /// ±9990 Hz, which needs two, so the second byte is probably its high half.
            public static let ritOffsetOffset = 8
            /// Records 0–31 are the band stack (two per band); 32–33 are the current VFO A/B.
            public static let currentVFORecordIndex = 32
            public static let bandRecordNames = [
                "160m A", "160m B", "80m A", "80m B", "60m A", "60m B", "40m A", "40m B",
                "30m A", "30m B", "20m A", "20m B", "17m A", "17m B", "15m A", "15m B",
                "12m A", "12m B", "11m A", "11m B", "6m A", "6m B", "GEN A", "GEN B",
                "Spare 1", "Spare 2", "Spare 3", "Spare 4", "Spare 5", "Spare 6", "Spare 7", "Spare 8",
                "VFO A", "VFO B",
            ]
            /// UInt16 LE Hz values, 4 presets each.
            public static let filterSSBLowStart = 0x228
            public static let filterSSBHighStart = 0x230
            public static let filterCWStart = 0x238
            public static let filterAMStart = 0x240
            public static let filterFMStart = 0x248
            public static let kilohertz = 1_000
            /// TX filters: SSB low, SSB high, AM, FM × 2 presets, UInt16 LE Hz.
            public static let txFilterStart = 0x250
            public static let txFilterPresetCount = 2
            public static let voxDelayMicOffset = 0x264
            public static let voxDelayCWOffset = 0x266
            public static let rxEQStart = 0x269
            public static let txEQStart = 0x26C
            public static let digGainOffset = 0x270
            public static let txPanScaleOffset = 0x284
            public static let txPanShiftOffset = 0x285
            public static let rxPanAverageOffset = 0x286
            public static let rxPanScaleOffset = 0x287
            public static let rxPanShiftOffset = 0x288
            /// Pan scale is stored ×10 (0.9 → 9).
            public static let panScaleFactor = 0.1
            public static let cwPitchOffset = 0x2A2
            /// Start of the menu-value area searched by CAT correlation (after band stack and filters).
            public static let menuAreaStart = 0x224
            /// Menu-area settings confirmed on firmware 1.30.00 (see SettingsLayout.discovered).
            public static let compressorOnOffOffset = 0x226
            public static let voxDelaySSBOffset = 0x264
            public static let voxDelayCWOffset2 = 0x266
            public static let voxDelayDIGOffset = 0x292
            public static let voxGainSSBOffset = 0x268
            public static let voxGainDIGOffset = 0x294
            public static let micGainOffset2 = 0x272
            public static let digGainOffset2 = 0x273
            public static let compressorLevelOffset = 0x274
            public static let txPowerOffset = 0x275
            public static let agcCWOffset = 0x277
            public static let agcSSBOffset = 0x278
            public static let squelchOffset = 0x27F
            public static let filterPresetOffset = 0x27C
            public static let nbLevelOffset = 0x282
            public static let nfTypeOffset = 0x283
            public static let afGainOffset = 0x28C
            public static let monitorLevelOffset = 0x28F
            public static let tunePowerOffset2 = 0x2A4
            /// From here to the end every backup so far is zero.
            public static let reservedStart = 0x2A8
        }
    }

    // MARK: Memory channels (MR read / MW write) — from Lab599 TRXMem 1.03

    public enum Memory {
        public static let readCommand = "MR"
        public static let writeCommand = "MW"
        /// Always "00" in front of the two-digit channel number.
        public static let bankPrefix = "00"
        public static let channelDigits = 2
        public static let channelRange = 0...99
        public static let frequencyDigits = 11
        /// Unused digits after the PRE/ATT digit.
        public static let reservedDigits = 22
        public static let nameLength = 8
        /// `MR00cc` + freq(11) + mode(1) + preAtt(1) + reserved(22) + name(8) + `;`.
        public static let recordLength = 50
        /// `MW` gets no answer; wait this long before reading the channel back to verify it.
        public static let writeSettleDelay: TimeInterval = 0.1

        /// Offsets within the record body (after `MR00cc`).
        public enum Layout {
            public static let headerLength = 6
            public static let frequency = 0..<11
            public static let mode = 11
            public static let preAtt = 12
            public static let name = 35..<43
        }

        /// `.mem` file: 100 × (Int32 LE frequency Hz, mode digit, PRE/ATT digit).
        ///
        /// The frequency is binary but the two trailing bytes are **ASCII digits**, as written by
        /// Lab599's TRXMem: a CW channel stores 0x33 ('3'), not 0x03, and an empty channel stores
        /// '0'/'0'. Verified against a .mem file exported by TRXMem itself.
        public static let fileExtension = "mem"
        public static let fileRecordSize = 6

        /// A single-digit value as the ASCII byte a `.mem` file stores.
        public static func fileDigit(_ value: Int) -> UInt8 {
            UInt8(ascii: "0") + UInt8(clamping: value)
        }

        /// The value behind a `.mem` file's ASCII digit; tolerates a raw binary byte from older files.
        public static func fileValue(_ byte: UInt8) -> Int {
            let zero = UInt8(ascii: "0")
            return byte >= zero ? Int(byte - zero) : Int(byte)
        }
    }

    // MARK: Clock (TM) — from Lab599 TRX-TimeSync

    public enum Clock {
        public static let command = "TM"
        public static let timeFormat = "HH:mm:ss"
        public static let responseLength = 11
        public static let verifyDelay: TimeInterval = 0.1
    }
}
