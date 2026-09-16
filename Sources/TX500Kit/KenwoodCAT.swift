import Foundation

public enum CATError: Error, LocalizedError, Equatable {
    case noResponse(String)
    case unsupported(String)
    case malformed(command: String, response: String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case let .noResponse(c): "Radio did not answer \(c)"
        case let .unsupported(c): "Radio does not support \(c)"
        case let .malformed(c, r): "Unexpected answer to \(c): \(r)"
        case let .invalidArgument(s): s
        }
    }
}

/// Serialized Kenwood-style CAT session for the TX-500.
///
/// The TX-500 echoes commands it does not implement (`FN;` → `FN;`), which is how
/// `query` distinguishes "unsupported" from "no answer".
public actor KenwoodCAT {
    private typealias P = TX500Protocol.CAT
    public static let baudRate = TX500Protocol.CAT.baudRate

    /// Internal so feature extensions (settings, memories) in this module can do custom framing.
    let transport: SerialTransport

    public init(transport: SerialTransport) {
        self.transport = transport
    }

    private static func terminated(_ command: String) -> String {
        command.hasSuffix(P.terminatorString) ? command : command + P.terminatorString
    }

    /// Sends a raw command (with or without `;`) and returns its response (empty if none arrived).
    ///
    /// Only a frame starting with the command's two-letter mnemonic is accepted. Stale frames
    /// (e.g. a late answer to an earlier command still in the USB adapter's buffer) are discarded,
    /// so one delayed reply can't shift every later answer by one.
    public func raw(_ command: String, timeout: TimeInterval = TX500Protocol.CAT.responseTimeout) throws -> String {
        let cmd = Self.terminated(command)
        guard !TransmitGuard.startsTransmission(cmd) else { throw TransmitGuardError.blocked(cmd) }
        let mnemonic = String(cmd.prefix(P.commandPrefixLength))
        try transport.flushInput()
        try transport.write(Data(cmd.utf8))
        let deadline = Date().addingTimeInterval(timeout)
        while deadline.timeIntervalSinceNow > 0 {
            let data = try transport.read(until: P.terminator, timeout: deadline.timeIntervalSinceNow)
            if data.isEmpty { break }
            let frame = String(decoding: data, as: UTF8.self)
            if frame.hasPrefix(mnemonic) { return frame }
        }
        return ""
    }

    /// Sends a get command and returns the response, throwing if missing or echoed.
    public func query(_ command: String) throws -> String {
        let cmd = Self.terminated(command)
        let r = try raw(cmd)
        if r.isEmpty { throw CATError.noResponse(cmd) }
        if r == cmd { throw CATError.unsupported(cmd) }
        return r
    }

    /// Sends a set command. Set commands produce no answer on Kenwood rigs.
    /// Commands that would key the transmitter are refused unless `allowTransmit` is true (see `TransmitGuard`).
    public func send(_ command: String, allowTransmit: Bool = false) throws {
        guard allowTransmit || !TransmitGuard.startsTransmission(command) else {
            throw TransmitGuardError.blocked(Self.terminated(command))
        }
        try transport.write(Data(Self.terminated(command).utf8))
        try transport.drainOutput()
        Thread.sleep(forTimeInterval: P.postSetDelay)
    }

    // MARK: Typed getters

    public func identify() throws -> String { try query("ID") }

    public func information() throws -> InformationFrame {
        let r = try query("IF")
        guard let f = InformationFrame(response: r) else { throw CATError.malformed(command: "IF;", response: r) }
        return f
    }

    public func frequency(vfo: VFO = .a) throws -> Int {
        try integer(vfo.command)
    }

    private func integer(_ command: String) throws -> Int {
        let r = try query(command)
        guard let v = CATResponse.integer(r, prefix: command) else {
            throw CATError.malformed(command: command, response: r)
        }
        return v
    }

    public func sMeter() throws -> Int { try integer("SM0") }

    private typealias Levels = TX500Protocol.CAT.Levels

    /// Reads a raw level and converts it to front-panel units.
    private func level(_ command: String, _ scale: LevelScale) throws -> Int {
        scale.display(fromRaw: try integer(command))
    }

    /// Output power in percent (10–100).
    public func powerPercent() throws -> Int { try level("PC", Levels.powerPercent) }

    /// Polls everything the Radio tab needs. Unsupported/missing optional values are left nil.
    public func readState() throws -> RigState {
        var s = RigState()
        s.info = try information()
        s.vfoA = try? frequency(vfo: .a)
        s.vfoB = try? frequency(vfo: .b)
        s.sMeter = try? sMeter()
        s.powerPercent = try? powerPercent()
        s.afGain = try? level("AG0", Levels.afGain)
        s.rfGainDB = try? level("RG", Levels.rfGain)
        s.squelch = try? integer("SQ0")
        s.keyerCPM = try? level("KS", Levels.keyerSpeed)
        s.vox = (try? integer("VX")).map { $0 != 0 }
        s.noiseBlanker = (try? integer("NB")).map { $0 != 0 }
        s.noiseReduction = (try? integer("NR")).map { $0 != 0 }
        s.locked = (try? leadingDigit("LK")).map { $0 != 0 }
        s.supplyVolts = try? supplyVoltage()
        s.agcTimeConstant = try? integer("GT")
        if let fl = try? query("FL"), let body = CATResponse.body(of: fl, command: "FL"), body.count == Self.filterAnswerDigits {
            s.rxFilterPreset = Int(String(body.first!))
            s.txFilterPreset = Int(String(body.last!))
        }
        // MO0 switches the monitor on, MO1 mutes it — confirmed on the radio, and matching the
        // protocol doc's "1: TX Monitor mute". So the monitor is audible when MO reads 0.
        s.monitorOn = (try? integer("MO")).map { $0 == 0 }
        s.monitorLevel = try? integer("ML")
        s.compressorOn = (try? integer("PR")).map { $0 != 0 }
        s.preampOn = (try? leadingDigit("PA")).map { $0 != 0 }
        s.attenuatorOn = (try? leadingDigit("RA", digits: Self.attenuatorStateDigits)).map { $0 != 0 }
        s.notchOn = (try? integer("NT")).map { $0 != 0 }
        s.ritOn = (try? integer("RT")).map { $0 != 0 }
        s.xitOn = (try? integer("XT")).map { $0 != 0 }
        s.splitOn = (try? integer("SP")).map { $0 != 0 }
        return s
    }

    /// `FL` answers two digits: RX preset, TX preset.
    private static let filterAnswerDigits = 2
    /// `RA` answers `P1P1P2P2`; the state is the first two digits.
    private static let attenuatorStateDigits = 2

    /// For answers like `PA00;` / `LK00;` / `RA0000;` where only the leading digits carry the state.
    private func leadingDigit(_ command: String, digits: Int = 1) throws -> Int {
        let r = try query(command)
        guard let body = CATResponse.body(of: r, command: command), let v = Int(body.prefix(digits)) else {
            throw CATError.malformed(command: command, response: r)
        }
        return v
    }

    /// Supply voltage from `VL` (answer `VL14.2 ;`).
    public func supplyVoltage() throws -> Double {
        let command = P.voltageCommand
        let r = try query(command)
        guard let body = CATResponse.body(of: r, command: command),
              let volts = Double(body.trimmingCharacters(in: .whitespaces)) else {
            throw CATError.malformed(command: command, response: r)
        }
        return volts
    }

    /// Reads just the settings bytes that hold filter passbands (~40 `XL` reads, a few seconds).
    public func readFilterTable() throws -> FilterTable {
        var bytes = [UInt8](repeating: 0, count: TX500Protocol.Settings.byteCount)
        for offset in FilterTable.requiredOffsets {
            let response = try raw(SettingsBackup.readCommand(index: offset), timeout: TX500Protocol.Settings.replyTimeout)
            guard let value = SettingsBackup.parseReadResponse(response) else {
                throw SettingsBackupError.readFailed(address: SettingsBackup.address(ofIndex: offset), response: response)
            }
            bytes[offset] = value
        }
        return FilterTable(bytes: bytes)
    }

    /// Fast poll used for live metering: IF + S-meter only.
    public func readLive(into state: inout RigState) throws {
        state.info = try information()
        state.sMeter = try? sMeter()
    }

    // MARK: Setters

    public func setFrequency(_ hz: Int, vfo: VFO = .a) throws {
        guard P.frequencyRangeHz.contains(hz) else { throw CATError.invalidArgument("Frequency out of range") }
        try send(vfo.command + Self.zeroPadded(hz, digits: P.frequencyDigits))
    }

    public func setMode(_ mode: OperatingMode) throws { try send("MD\(mode.rawValue)") }

    /// Sets a level given in front-panel units; rejects values outside the radio's range.
    private func setLevel(_ command: String, _ scale: LevelScale, _ value: Int, name: String) throws {
        guard scale.displayRange.contains(value) else {
            throw CATError.invalidArgument("\(name) must be \(scale.formatted(scale.displayRange.lowerBound))–\(scale.formatted(scale.displayRange.upperBound))")
        }
        try send(command + String(format: P.threeDigitField, scale.raw(fromDisplay: value)))
    }

    public func setPower(percent: Int) throws { try setLevel("PC", Levels.powerPercent, percent, name: "Power") }
    public func setAFGain(_ value: Int) throws { try setLevel("AG0", Levels.afGain, value, name: "AF gain") }
    public func setRFGain(dB: Int) throws { try setLevel("RG", Levels.rfGain, dB, name: "RF gain") }
    public func setKeyerSpeed(cpm: Int) throws { try setLevel("KS", Levels.keyerSpeed, cpm, name: "Keyer speed") }

    /// Keys the transmitter. Callers must obtain explicit user confirmation first.
    public func transmit(_ on: Bool) throws { try send(on ? "TX" : "RX", allowTransmit: on) }

    static func zeroPadded(_ value: Int, digits: Int) -> String {
        let s = String(value)
        return String(repeating: "0", count: max(0, digits - s.count)) + s
    }

    // MARK: Diagnostics

    public enum ProbeResult: Sendable, Equatable {
        case answered(String), echoed, silent
    }

    public func probe(_ commands: [String]) throws -> [(String, ProbeResult)] {
        try commands.map { c in
            let cmd = Self.terminated(c)
            let r = try raw(cmd, timeout: P.probeTimeout)
            if r.isEmpty { return (cmd, .silent) }
            if r == cmd { return (cmd, .echoed) }
            return (cmd, .answered(r))
        }
    }

    /// Read-only get commands known (or suspected) to exist on the TX-500.
    /// Read commands from Lab599 CAT Protocol r3, plus a few legacy/TS-2000 ones to show as unsupported.
    /// Commands that act without a value (TX, RX, VV, BD/BU, SC, QR, VR) are deliberately absent.
    public static let probeCommands = [
        "ID", "IF", "FA", "FB", "MD", "FR", "FT", "AI", "SM0", "RM", "BY", "PT", "PS",
        "PC", "TP", "CG", "AG0", "RG", "SQ0", "GT", "PA", "RA", "FL", "IS", "AL",
        "NB", "NL", "NR", "NT", "NF", "RL", "ML", "MO", "MG", "MA", "PL", "PR",
        "KS", "VX", "VG", "VD", "LK", "SP", "RT", "XT", "TO", "MC", "MR0001", "VL", "TM", "EX",
        "AC", "CN", "CT", "FN", "SH", "SL", "TY", "FV",
    ]
}

public enum VFO: String, CaseIterable, Sendable {
    case a = "A", b = "B"
    var command: String { "F" + rawValue }
}
