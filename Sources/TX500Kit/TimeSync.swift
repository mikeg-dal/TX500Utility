import Foundation

public enum TimeSyncError: Error, LocalizedError, Equatable {
    case unsupported
    case notConfirmed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported: "This firmware does not support setting the clock (TM). Update the firmware first."
        case let .notConfirmed(r): "Radio did not confirm the new time (\(r.isEmpty ? "no answer" : r))"
        }
    }
}

extension KenwoodCAT {
    private static func clockFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = TX500Protocol.Clock.timeFormat
        return f
    }

    static func clockSetCommand(for date: Date) -> String {
        TX500Protocol.Clock.command + clockFormatter().string(from: date) + TX500Protocol.CAT.terminatorString
    }

    /// Reads the radio clock (`TM;` → `TMhh:mm:ss;`). Throws `.unsupported` on firmware without TM.
    public func radioTime() throws -> String {
        do {
            let r = try query(TX500Protocol.Clock.command)
            guard r.count == TX500Protocol.Clock.responseLength,
                  let body = CATResponse.body(of: r, command: TX500Protocol.Clock.command) else {
                throw TimeSyncError.notConfirmed(r)
            }
            return body
        } catch CATError.unsupported {
            throw TimeSyncError.unsupported
        }
    }

    /// Sets the radio clock to `date` (local time), then reads it back — same sequence as TRX-TimeSync.
    @discardableResult
    public func syncClock(to date: Date = Date()) throws -> String {
        try send(Self.clockSetCommand(for: date))
        Thread.sleep(forTimeInterval: TX500Protocol.Clock.verifyDelay)
        return try radioTime()
    }
}
