import Foundation

public enum TransmitGuardError: Error, LocalizedError, Equatable {
    case blocked(String)

    public var errorDescription: String? {
        switch self {
        case let .blocked(cmd): "Blocked \(cmd): this command makes the radio transmit and was not sent as an explicit transmit action."
        }
    }
}

/// Recognizes set commands that key the transmitter, so they can never be sent by accident.
///
/// From Lab599 CAT Protocol r3:
/// - `TX;` sets transmit mode.
/// - `CGnnn;` with nnn 010–100 sets the TUNE/TONE level **and turns TX on** (`CG000;` turns it off).
/// - `AC0x1;` starts the internal tuner (TX-500MP), which transmits a tuning carrier.
public enum TransmitGuard {
    public static func startsTransmission(_ command: String) -> Bool {
        let cmd = command.hasSuffix(TX500Protocol.CAT.terminatorString) ? String(command.dropLast()) : command
        if cmd == "TX" { return true }
        if cmd.hasPrefix("CG"), let level = Int(cmd.dropFirst(2)), level > 0 { return true }
        if cmd.hasPrefix("AC"), cmd.count == 5, cmd.last == "1" { return true }
        return false
    }
}
