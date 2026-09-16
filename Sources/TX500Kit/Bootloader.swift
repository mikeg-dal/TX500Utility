import Foundation

/// Errors mirror the vendor updater's result codes (Lab599 Firmware Update 1.0.1 / 1.0.2).
public enum BootloaderError: Error, LocalizedError, Equatable {
    /// Vendor "ERROR:3 Device does not respond!" — no answer within 5 s.
    case deviceDoesNotRespond
    /// Vendor "ERROR:4 No correct answer device!" — header answer was not `OK`.
    case unexpectedHeaderAnswer(Data)
    /// Vendor "ERROR:5 Update wrong!" — final answer was not `OK`.
    case updateRejected(Data)

    public var errorDescription: String? {
        switch self {
        case .deviceDoesNotRespond:
            "The radio did not respond. Make sure it shows “The loader is waiting…” (power off, then hold the third button from the left in the row above the screen while pressing POWER)."
        case let .unexpectedHeaderAnswer(d):
            "The loader rejected the firmware header (answer: \(Self.describe(d))). The file may not match this radio."
        case let .updateRejected(d):
            "The loader reported a failed update (answer: \(Self.describe(d))). Power-cycle into loader mode and try again."
        }
    }

    private static func describe(_ d: Data) -> String {
        d.isEmpty ? "none" : d.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// Firmware transfer to the TX-500 bootloader.
///
/// Protocol (57600 8N1, no flow control):
/// 1. wait 100 ms, discard pending input
/// 2. send the 16-byte header → loader answers `OK`
/// 3. stream the payload with no per-block acknowledgements
/// 4. loader answers `OK` when the image has been accepted
public actor Bootloader {
    public enum Phase: Sendable, Equatable {
        case handshaking
        case transferring(sent: Int, total: Int)
        case verifying
        case finished
    }

    public typealias PhaseHandler = @Sendable (Phase) -> Void
    private typealias B = TX500Protocol.Bootloader

    private let transport: SerialTransport

    /// `transport` must already be open at `TX500Protocol.Bootloader.baudRate`.
    public init(transport: SerialTransport) {
        self.transport = transport
    }

    /// Sends only the header and checks for `OK`. **Not a safe test:** verified on a TX-500 (2026-09-15) that
    /// once the header is accepted the loader erases the application firmware, so the radio then boots
    /// straight into the loader until a full `update` completes. Developer diagnostics only; not used by the app.
    public func checkHandshake(image: FirmwareImage) throws {
        try handshake(image)
    }

    /// Full update. Do not interrupt once `transferring` has started.
    public func update(image: FirmwareImage, onPhase: PhaseHandler? = nil) throws {
        onPhase?(.handshaking)
        try handshake(image)

        let payload = image.payload
        let total = payload.count
        var sent = 0
        onPhase?(.transferring(sent: sent, total: total))
        while sent < total {
            let end = min(sent + B.chunkSize, total)
            try transport.write(payload.subdata(in: (payload.startIndex + sent)..<(payload.startIndex + end)))
            try transport.drainOutput()
            sent = end
            onPhase?(.transferring(sent: sent, total: total))
        }

        onPhase?(.verifying)
        let answer = try transport.read(exactly: B.acknowledgement.count, timeout: B.answerTimeout)
        guard !answer.isEmpty else { throw BootloaderError.deviceDoesNotRespond }
        guard answer == B.acknowledgement else { throw BootloaderError.updateRejected(answer) }
        onPhase?(.finished)
    }

    private func handshake(_ image: FirmwareImage) throws {
        Thread.sleep(forTimeInterval: B.settleDelay)
        try transport.flushInput()
        try transport.write(image.header)
        try transport.drainOutput()
        let answer = try transport.read(exactly: B.acknowledgement.count, timeout: B.answerTimeout)
        guard !answer.isEmpty else { throw BootloaderError.deviceDoesNotRespond }
        guard answer == B.acknowledgement else { throw BootloaderError.unexpectedHeaderAnswer(answer) }
    }
}
