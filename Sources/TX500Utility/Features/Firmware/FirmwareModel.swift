import Foundation
import Observation
import TX500Kit

/// Drives the firmware update flow. Takes exclusive ownership of the serial port while talking to the loader.
@MainActor
@Observable
final class FirmwareModel {
    enum Stage: Equatable {
        case idle
        case updating(Bootloader.Phase)
        case succeeded
        case failed(String)
    }

    private(set) var image: FirmwareImage?
    private(set) var stage: Stage = .idle
    var imageError: String?
    var loaderModeConfirmed = false
    /// Set when opening this page closed an active CAT connection, so the page can say it happened
    /// rather than leaving the user wondering why the radio went quiet.
    private(set) var didDisconnect = false
    /// The port to talk to the loader on, remembered when the connection is closed.
    private(set) var portPath: String?
    private(set) var isBackingUp = false
    private(set) var backupMessage: BackupMessage?

    enum BackupMessage: Equatable {
        case success(String)
        case failure(String)
    }

    /// Releases the serial port as soon as the page opens.
    ///
    /// A radio in loader mode does not answer CAT, so a connection left open just polls a silent
    /// radio and fills the page with errors at the exact moment the user is following instructions.
    /// Disconnecting up front makes that impossible rather than merely discouraged.
    func prepare(connection: RadioConnection) {
        portPath = connection.selectedPortPath
        guard connection.isConnected else { return }
        portPath = connection.releasePort() ?? portPath
        didDisconnect = true
    }

    /// Backs the radio up from this page: reconnects, reads the settings, saves them, disconnects again.
    ///
    /// The page releases the port on open, so telling the user to go and back up elsewhere would mean
    /// reconnecting by hand, switching pages, and coming back — which disconnects them again. Doing
    /// the whole round trip here keeps the port released everywhere except for the read itself.
    func backUpNow(connection: RadioConnection, loader: RadioLoader, store: BackupStore) async {
        backupMessage = nil
        isBackingUp = true
        defer { isBackingUp = false }

        await connection.connect()
        guard connection.isConnected else {
            backupMessage = .failure(connection.lastError ?? "Could not connect to the radio.")
            connection.lastError = nil
            return
        }
        var backup: SettingsBackup?
        await connection.perform { cat in backup = try await cat.readSettings() }
        let readError = connection.lastError
        connection.lastError = nil
        portPath = connection.releasePort() ?? portPath      // straight back to released

        guard let backup else {
            backupMessage = .failure(readError ?? "Could not read the radio's settings.")
            return
        }
        loader.updateSettings(backup)
        do {
            try store.save(backup)
            backupMessage = .success("Backed up \(Date().formatted(date: .abbreviated, time: .shortened)). CAT released again.")
        } catch {
            backupMessage = .failure(error.localizedDescription)
        }
    }

    /// Reconnects after an update so the user can see the version the radio is actually running.
    func reconnect(loader: RadioLoader) async {
        didDisconnect = false
        stage = .idle
        await loader.connectAndLoad()
    }

    var isWorking: Bool {
        switch stage {
        case .updating: true
        default: false
        }
    }

    var transferFraction: Double? {
        guard case let .updating(.transferring(sent, total)) = stage, total > 0 else { return nil }
        return Double(sent) / Double(total)
    }

    func chooseFile() {
        guard let url = FilePanels.openFile(extension: FirmwareModel.fileExtension, message: "Choose TX-500 firmware (.fw)") else { return }
        do {
            image = try FirmwareImage(contentsOf: url)
            imageError = nil
            stage = .idle
        } catch {
            image = nil
            imageError = error.localizedDescription
        }
    }

    func update(connection: RadioConnection) async {
        guard let image, let path = takePort(connection) else { return }
        stage = .updating(.handshaking)
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Updating TX-500 firmware")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        // The inner Task captures this closure rather than self: capturing a weak self across a
        // concurrency boundary is rejected by older toolchains ("reference to captured var 'self'").
        let onMain: @MainActor @Sendable (Bootloader.Phase) -> Void = { [weak self] phase in
            self?.apply(phase)
        }
        let report: Bootloader.PhaseHandler = { phase in
            Task { @MainActor in onMain(phase) }
        }
        do {
            try await withLoader(path: path) { try await $0.update(image: image, onPhase: report) }
            stage = .succeeded
        } catch {
            stage = .failed(error.localizedDescription)
        }
        loaderModeConfirmed = false
    }

    func reset() {
        stage = .idle
    }

    // MARK: Private

    static let fileExtension = "fw"

    /// Progress callbacks can arrive after completion; never regress a final stage.
    private func apply(_ phase: Bootloader.Phase) {
        guard case .updating = stage else { return }
        stage = .updating(phase)
    }

    private func takePort(_ connection: RadioConnection) -> String? {
        // The page disconnects on open, so the port is normally the one remembered then; fall back
        // to the current selection in case it was chosen afterwards.
        let path = connection.isConnected ? connection.releasePort() : (portPath ?? connection.selectedPortPath)
        if path == nil { stage = .failed("Select the CAT cable's serial port first.") }
        return path
    }

    private func withLoader(path: String, _ body: @escaping @Sendable (Bootloader) async throws -> Void) async throws {
        try await Task.detached(priority: .userInitiated) {
            let port = SerialPort(path: path, baudRate: TX500Protocol.Bootloader.baudRate)
            try port.open()
            defer { port.close() }
            try await body(Bootloader(transport: port))
        }.value
    }
}
