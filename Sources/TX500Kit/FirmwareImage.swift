import CryptoKit
import Foundation

public enum FirmwareImageError: Error, LocalizedError, Equatable {
    case badMagic
    case sizeOutOfRange(Int)

    public var errorDescription: String? {
        switch self {
        case .badMagic: "Not a TX-500 firmware file (missing BL20 header)"
        case let .sizeOutOfRange(n): "Firmware file size \(n) bytes is outside the expected range"
        }
    }
}

/// A validated `.fw` image: 16-byte header (starting with `BL20`) followed by the encrypted payload.
/// The payload is sent to the loader unchanged; it is never decrypted or modified here.
public struct FirmwareImage: Sendable, Equatable {
    public let data: Data
    public let fileName: String

    public init(data: Data, fileName: String) throws {
        let b = TX500Protocol.Bootloader.self
        guard b.imageSizeRange.contains(data.count) else { throw FirmwareImageError.sizeOutOfRange(data.count) }
        guard data.prefix(b.magic.count) == b.magic else { throw FirmwareImageError.badMagic }
        self.data = data
        self.fileName = fileName
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url), fileName: url.lastPathComponent)
    }

    public var header: Data { data.prefix(TX500Protocol.Bootloader.headerLength) }
    public var payload: Data { data.dropFirst(TX500Protocol.Bootloader.headerLength) }

    /// Version parsed from the vendor naming scheme, e.g. `mtrx1.30.00.fw` → "1.30.00".
    public var versionFromFileName: String? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let start = stem.firstIndex(where: \.isNumber) else { return nil }
        return String(stem[start...])
    }

    public var sha256: String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
