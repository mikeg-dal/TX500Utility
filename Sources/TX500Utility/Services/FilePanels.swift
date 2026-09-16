import AppKit
import UniformTypeIdentifiers

/// Thin wrappers over NSOpenPanel / NSSavePanel so features don't repeat panel setup.
@MainActor
enum FilePanels {
    static func openFile(extension ext: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveFile(extension ext: String, suggestedName: String, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.message = message
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        panel.nameFieldStringValue = suggestedName
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
