import Foundation
import TX500Kit

// Small companion CLI for exercising TX500Kit against the radio from the terminal.
//   tx500 ports
//   tx500 status [--port /dev/cu.xxx]
//   tx500 watch  [--port ...]
//   tx500 probe  [--port ...]
//   tx500 settings [out.set]   (read-only backup)
//   tx500 memories
//   tx500 fw-info file.fw
//   tx500 fw-test file.fw     (loader mode; header-only handshake)
//   tx500 raw "FA;" [--port ...]

var args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let portPath = option("--port") ?? PortDiscovery.availablePorts().first(where: \.isLikelyTX500Cable)?.path
let command = args.first ?? "status"

func withCAT(_ body: (KenwoodCAT) async throws -> Void) async {
    guard let portPath else { fail("No FTDI/PL2303 serial port found; pass --port") }
    let port = SerialPort(path: portPath, baudRate: KenwoodCAT.baudRate)
    do {
        try port.open()
        try await body(KenwoodCAT(transport: port))
    } catch {
        fail("Error: \(error.localizedDescription)")
    }
    port.close()
}

func describe(_ s: RigState) -> String {
    var parts: [String] = []
    if let f = s.frequencyHz { parts.append("VFO \(FrequencyFormat.dotted(f))") }
    if let m = s.mode { parts.append(m.label) }
    if let b = s.vfoB { parts.append("B \(FrequencyFormat.dotted(b))") }
    if let sm = s.sMeter { parts.append("S \(sm)") }
    let levels = TX500Protocol.CAT.Levels.self
    if let p = s.powerPercent { parts.append("PWR " + levels.powerPercent.formatted(p)) }
    if let a = s.afGain { parts.append("AF " + levels.afGain.formatted(a)) }
    if let r = s.rfGainDB { parts.append("RF " + levels.rfGain.formatted(r)) }
    if let k = s.keyerCPM { parts.append(levels.keyerSpeed.formatted(k)) }
    if let v = s.vox { parts.append("VOX \(v ? "on" : "off")") }
    parts.append(s.transmitting ? "TX" : "RX")
    return parts.joined(separator: "  ")
}

switch command {
case "ports":
    for p in PortDiscovery.availablePorts() {
        let ids = p.vendorID.map { String(format: "%04X:%04X", $0, p.productID ?? 0) } ?? "-"
        print("\(p.path)\t\(ids)\t\(p.chipset.rawValue)\t\(p.productName ?? "")")
    }

case "status":
    await withCAT { cat in
        print("Port:", portPath!)
        print("ID:  ", try await cat.identify())
        print(describe(try await cat.readState()))
    }

case "watch":
    await withCAT { cat in
        var state = try await cat.readState()
        while true {
            try await cat.readLive(into: &state)
            print("\r" + describe(state) + "      ", terminator: "")
            fflush(stdout)
            try await Task.sleep(for: TX500Protocol.CAT.livePollInterval)
        }
    }

case "probe":
    await withCAT { cat in
        for (cmd, result) in try await cat.probe(KenwoodCAT.probeCommands) {
            switch result {
            case let .answered(r): print(cmd.padding(toLength: 6, withPad: " ", startingAt: 0), r)
            case .echoed: print(cmd.padding(toLength: 6, withPad: " ", startingAt: 0), "(unsupported)")
            case .silent: print(cmd.padding(toLength: 6, withPad: " ", startingAt: 0), "(no answer)")
            }
        }
    }

case "settings":
    // tx500 settings [out.set] — read-only backup of the 1024-byte settings table
    await withCAT { cat in
        let backup = try await cat.readSettings { done, total in
            print("\rReading settings \(done)/\(total)", terminator: "")
            fflush(stdout)
        }
        print()
        let out = args.count >= 2 ? args[1] : "TX500-settings.\(TX500Protocol.Settings.fileExtension)"
        try backup.fileData.write(to: URL(fileURLWithPath: out))
        print("Saved \(out)")
    }

case "memories":
    await withCAT { cat in
        for ch in try await cat.readMemories() where !ch.isEmpty {
            print(String(format: "%02d", ch.number), FrequencyFormat.dotted(ch.frequencyHz), ch.mode?.label ?? "-", ch.preAtt.label, ch.name)
        }
        print("Done.")
    }

case "fw-info":
    guard args.count >= 2 else { fail("usage: tx500 fw-info file.fw") }
    do {
        let image = try FirmwareImage(contentsOf: URL(fileURLWithPath: args[1]))
        print("\(image.fileName)  version \(image.versionFromFileName ?? "?")  \(image.data.count) bytes")
        print("header  \(image.header.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("sha256  \(image.sha256)")
    } catch {
        fail("Error: \(error.localizedDescription)")
    }

case "fw-test":
    // tx500 fw-test file.fw — radio must show "The loader is waiting…". Sends ONLY the 16-byte header.
    // WARNING: the loader erases the radio's firmware once it accepts the header. A full update must follow.
    guard args.count >= 2 else { fail("usage: tx500 fw-test file.fw") }
    guard let portPath else { fail("No FTDI/PL2303 serial port found; pass --port") }
    do {
        let image = try FirmwareImage(contentsOf: URL(fileURLWithPath: args[1]))
        let port = SerialPort(path: portPath, baudRate: TX500Protocol.Bootloader.baudRate)
        try port.open()
        defer { port.close() }
        print("Sending 16-byte header to loader on \(portPath) at \(TX500Protocol.Bootloader.baudRate)…")
        try await Bootloader(transport: port).checkHandshake(image: image)
        print("Loader answered OK. The radio's firmware is now erased; run a full update before power-cycling.")
    } catch {
        fail("Error: \(error.localizedDescription)")
    }

case "raw":
    guard args.count >= 2 else { fail("usage: tx500 raw \"FA;\"") }
    await withCAT { cat in print(try await cat.raw(args[1])) }

default:
    fail("unknown command \(command). Commands: ports, status, watch, probe, settings, memories, fw-info, fw-test, raw")
}
