import Foundation
import IOKit
import IOKit.serial
import IOKit.usb

public struct SerialPortInfo: Identifiable, Hashable, Sendable {
    public enum Chipset: String, Sendable { case ftdi = "FTDI FT232", prolific = "Prolific PL2303", other = "Serial" }

    public var id: String { path }
    public let path: String
    public let vendorID: Int?
    public let productID: Int?
    public let productName: String?

    public var chipset: Chipset {
        switch vendorID {
        case TX500Protocol.USB.ftdiVendorID: return .ftdi
        case TX500Protocol.USB.prolificVendorID: return .prolific
        default: return .other
        }
    }

    /// True for the adapters Lab599 ships with the CAT cable.
    public var isLikelyTX500Cable: Bool { chipset != .other }

    public var displayName: String {
        let name = (path as NSString).lastPathComponent
        return chipset == .other ? name : "\(name) — \(chipset.rawValue)"
    }
}

public enum PortDiscovery {
    /// All callout (`/dev/cu.*`) serial devices, TX-500 cable chipsets first.
    public static func availablePorts() -> [SerialPortInfo] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary? else { return [] }
        matching[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var ports: [SerialPortInfo] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String else { continue }
            if path.contains("Bluetooth") || path.contains("debug-console") { continue }

            let vid = searchParents(service, key: kUSBVendorID) as? Int
            let pid = searchParents(service, key: kUSBProductID) as? Int
            let name = searchParents(service, key: kUSBProductString) as? String
            ports.append(SerialPortInfo(path: path, vendorID: vid, productID: pid, productName: name))
        }
        return ports.sorted { ($0.isLikelyTX500Cable ? 0 : 1, $0.path) < ($1.isLikelyTX500Cable ? 0 : 1, $1.path) }
    }

    private static func searchParents(_ service: io_object_t, key: String) -> Any? {
        IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }
}
