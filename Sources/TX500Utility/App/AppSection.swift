import SwiftUI

/// Sidebar destinations. To add a feature: add a case, give it a title/icon, and return its view in `RootView`.
enum AppSection: String, CaseIterable, Identifiable {
    case radio, memories, settings, clock, firmware, diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radio: "Radio"
        case .memories: "Memories"
        case .settings: "Settings Backups"
        case .clock: "Clock"
        case .firmware: "Firmware"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .radio: "dial.medium"
        case .memories: "list.number"
        case .settings: "externaldrive"
        case .clock: "clock"
        case .firmware: "arrow.down.circle"
        case .diagnostics: "stethoscope"
        }
    }
}
