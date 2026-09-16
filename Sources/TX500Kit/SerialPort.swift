import Foundation

public enum SerialError: Error, LocalizedError, Equatable {
    case openFailed(path: String, errno: Int32)
    case configureFailed(String, errno: Int32)
    case writeFailed(errno: Int32)
    case readFailed(errno: Int32)
    case notOpen
    case timeout

    public var errorDescription: String? {
        switch self {
        case let .openFailed(path, e): return "Can't open \(path): \(String(cString: strerror(e)))"
        case let .configureFailed(what, e): return "Serial configure (\(what)) failed: \(String(cString: strerror(e)))"
        case let .writeFailed(e): return "Serial write failed: \(String(cString: strerror(e)))"
        case let .readFailed(e): return "Serial read failed: \(String(cString: strerror(e)))"
        case .notOpen: return "Serial port is not open"
        case .timeout: return "Timed out waiting for the radio"
        }
    }
}

/// Minimal byte transport, so protocol code can be tested against a mock.
public protocol SerialTransport: AnyObject {
    func write(_ data: Data) throws
    /// Returns whatever bytes arrive within `timeout` (possibly empty).
    func read(maxCount: Int, timeout: TimeInterval) throws -> Data
    func drainOutput() throws
    func flushInput() throws
    func bytesAvailable() throws -> Int
}

/// ioctl request codes defined as C function-like macros, which Swift cannot import.
private enum IOCTL {
    /// `_IOW('T', 2, speed_t)` from IOKit/serial/ioss.h — set arbitrary baud rate.
    static let setSpeed: UInt = 0x8008_5402
    /// `_IOR('f', 127, int)` from sys/filio.h — bytes waiting in the input queue.
    static let bytesReadable: UInt = 0x4004_667F
}

/// POSIX termios serial port, raw 8N1, no flow control, DTR/RTS cleared on open.
public final class SerialPort: SerialTransport, @unchecked Sendable {
    public let path: String
    public private(set) var baudRate: Int
    private static let closedDescriptor: Int32 = -1
    private var fd: Int32 = SerialPort.closedDescriptor

    public var isOpen: Bool { fd >= 0 }

    private static let millisecondsPerSecond: TimeInterval = 1000
    /// USB-serial adapters can deliver bytes still buffered in the chip after `tcflush`;
    /// wait this long after opening, then discard whatever arrives.
    private static let openSettleDelay: TimeInterval = 0.1
    /// Input is considered drained once no byte arrives for this long.
    private static let staleInputQuietTime: TimeInterval = 0.05
    private static let staleReadChunk = 256

    public init(path: String, baudRate: Int) {
        self.path = path
        self.baudRate = baudRate
    }

    deinit { close() }

    public func open() throws {
        guard fd < 0 else { return }
        let f = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard f >= 0 else { throw SerialError.openFailed(path: path, errno: errno) }
        fd = f
        do {
            // Exclusive access so another app can't talk over us.
            if ioctl(fd, TIOCEXCL) == -1 { throw SerialError.configureFailed("TIOCEXCL", errno: errno) }
            // Back to blocking; reads are bounded with poll().
            if fcntl(fd, F_SETFL, 0) == -1 { throw SerialError.configureFailed("fcntl", errno: errno) }

            var t = termios()
            if tcgetattr(fd, &t) == -1 { throw SerialError.configureFailed("tcgetattr", errno: errno) }
            cfmakeraw(&t)
            t.c_cflag &= ~tcflag_t(CSIZE | PARENB | CSTOPB | CRTSCTS)
            t.c_cflag |= tcflag_t(CS8 | CREAD | CLOCAL)
            t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
            withUnsafeMutableBytes(of: &t.c_cc) { cc in
                cc[Int(VMIN)] = 0
                cc[Int(VTIME)] = 0
            }
            cfsetspeed(&t, speed_t(B9600))
            if tcsetattr(fd, TCSANOW, &t) == -1 { throw SerialError.configureFailed("tcsetattr", errno: errno) }
            try setBaud(baudRate)

            var bits = TIOCM_DTR | TIOCM_RTS
            _ = ioctl(fd, TIOCMBIC, &bits)
            tcflush(fd, TCIOFLUSH)
            Thread.sleep(forTimeInterval: Self.openSettleDelay)
            try discardStaleInput()
        } catch {
            close()
            throw error
        }
    }

    public func close() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = SerialPort.closedDescriptor
    }

    /// IOSSIOSPEED accepts any rate the driver supports (57600 for the bootloader, etc.).
    public func setBaud(_ baud: Int) throws {
        guard fd >= 0 else { throw SerialError.notOpen }
        var speed = speed_t(baud)
        if ioctl(fd, IOCTL.setSpeed, &speed) == -1 { throw SerialError.configureFailed("IOSSIOSPEED \(baud)", errno: errno) }
        baudRate = baud
    }

    public func write(_ data: Data) throws {
        guard fd >= 0 else { throw SerialError.notOpen }
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buf.count {
                let n = Darwin.write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    throw SerialError.writeFailed(errno: errno)
                }
                offset += n
            }
        }
    }

    public func read(maxCount: Int, timeout: TimeInterval) throws -> Data {
        guard fd >= 0 else { throw SerialError.notOpen }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let r = poll(&pfd, 1, Int32(max(0, timeout * SerialPort.millisecondsPerSecond)))
        if r < 0 {
            if errno == EINTR { return Data() }
            throw SerialError.readFailed(errno: errno)
        }
        if r == 0 { return Data() }
        var buf = [UInt8](repeating: 0, count: maxCount)
        let n = Darwin.read(fd, &buf, maxCount)
        if n < 0 {
            if errno == EINTR || errno == EAGAIN { return Data() }
            throw SerialError.readFailed(errno: errno)
        }
        return Data(buf.prefix(n))
    }

    /// Reads and throws away input until the line has been quiet for `staleInputQuietTime`.
    public func discardStaleInput() throws {
        while !(try read(maxCount: Self.staleReadChunk, timeout: Self.staleInputQuietTime)).isEmpty {}
    }

    public func drainOutput() throws {
        guard fd >= 0 else { throw SerialError.notOpen }
        if tcdrain(fd) == -1 && errno != EINTR { throw SerialError.writeFailed(errno: errno) }
    }

    public func flushInput() throws {
        guard fd >= 0 else { throw SerialError.notOpen }
        tcflush(fd, TCIFLUSH)
    }

    public func bytesAvailable() throws -> Int {
        guard fd >= 0 else { throw SerialError.notOpen }
        var n: Int32 = 0
        if ioctl(fd, IOCTL.bytesReadable, &n) == -1 { throw SerialError.readFailed(errno: errno) }
        return Int(n)
    }
}

extension SerialTransport {
    /// Reads until `count` bytes have arrived or `timeout` elapses.
    public func read(exactly count: Int, timeout: TimeInterval) throws -> Data {
        var out = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while out.count < count {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            out += try read(maxCount: count - out.count, timeout: remaining)
        }
        return out
    }

    /// Reads until `terminator` is seen or `timeout` elapses.
    public func read(until terminator: UInt8, timeout: TimeInterval) throws -> Data {
        var out = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return out }
            let chunk = try read(maxCount: 1, timeout: remaining)
            out += chunk
            if chunk.last == terminator { return out }
        }
    }
}
