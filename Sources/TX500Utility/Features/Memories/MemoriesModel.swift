import Foundation
import Observation
import TX500Kit

/// Memory channel editor: read from radio, edit, import/export `.mem`, write changes back.
@MainActor
@Observable
final class MemoriesModel {
    var channels: [MemoryChannel] = TX500Protocol.Memory.channelRange.map { MemoryChannel(number: $0) }
    /// Channels as last read from (or written to) the radio; used to write only what changed.
    private(set) var radioChannels: [MemoryChannel]?
    private(set) var progress: OperationProgress?
    var errorMessage: String?
    var statusMessage: String?

    var isBusy: Bool { progress != nil }

    var changedChannels: [MemoryChannel] {
        guard let radioChannels else { return channels.filter { !$0.isEmpty } }
        return zip(channels, radioChannels).filter { $0 != $1 }.map(\.0)
    }

    /// Uses channels already loaded (e.g. by the connect-time loader) unless the user has read or edited here.
    func adoptIfFresh(_ loaded: [MemoryChannel]?) {
        guard radioChannels == nil, let loaded else { return }
        channels = loaded
        radioChannels = loaded
    }

    func readFromRadio(connection: RadioConnection, loader: RadioLoader) async {
        let title = "Reading memories"
        progress = OperationProgress(title: title, completed: 0, total: TX500Protocol.Memory.channelRange.count)
        await connection.perform { [weak self] cat in
            let read = try await cat.readMemories { done, total in
                Task { @MainActor in self?.progress = OperationProgress(title: title, completed: done, total: total) }
            }
            await MainActor.run {
                self?.channels = read
                self?.radioChannels = read
                loader.updateMemories(read)
            }
        }
        finish(connection, success: "Read \(TX500Protocol.Memory.channelRange.count) channels.")
    }

    func writeChanges(connection: RadioConnection, loader: RadioLoader) async {
        let pending = changedChannels
        guard !pending.isEmpty else { return }
        let title = "Writing memories"
        progress = OperationProgress(title: title, completed: 0, total: pending.count)
        await connection.perform { [weak self] cat in
            try await cat.writeMemories(pending) { done, total in
                Task { @MainActor in self?.progress = OperationProgress(title: title, completed: done, total: total) }
            }
            await MainActor.run {
                self?.radioChannels = self?.channels
                if let channels = self?.channels { loader.updateMemories(channels) }
            }
        }
        finish(connection, success: "Wrote \(pending.count) channel(s).")
    }

    func clear(_ number: Int) {
        guard let i = channels.firstIndex(where: { $0.number == number }) else { return }
        channels[i] = MemoryChannel(number: number)
    }

    func importFile() {
        guard let url = FilePanels.openFile(extension: TX500Protocol.Memory.fileExtension,
                                            message: "Choose a TRXMem file (.mem)") else { return }
        do {
            channels = try MemoryFile.decode(Data(contentsOf: url))
            statusMessage = "Imported \(url.lastPathComponent). Review, then write to the radio."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportFile() {
        guard let url = FilePanels.saveFile(extension: TX500Protocol.Memory.fileExtension,
                                            suggestedName: "TX500-memories." + TX500Protocol.Memory.fileExtension,
                                            message: "Export memory channels") else { return }
        do {
            try MemoryFile.encode(channels).write(to: url, options: .atomic)
            statusMessage = "Exported \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish(_ connection: RadioConnection, success: String) {
        progress = nil
        if let error = connection.lastError {
            errorMessage = error
            connection.lastError = nil
        } else {
            statusMessage = success
        }
    }
}
