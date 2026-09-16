import Foundation
import Observation
import TX500Kit

/// Reads everything the app can show from the radio right after connecting, so every section is
/// already populated when the user opens it. Holds the loaded data for features to use.
@MainActor
@Observable
final class RadioLoader {
    enum Step: Int, CaseIterable, Identifiable {
        case radioState, filters, clock, memories, settings, backup

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .radioState: "Radio status"
            case .filters: "Filter presets"
            case .clock: "Clock support"
            case .memories: "Memory channels"
            case .settings: "Menu settings"
            case .backup: "Automatic backup"
            }
        }

        /// Relative duration, so the overall bar moves at a steady pace.
        var weight: Double {
            switch self {
            case .radioState, .clock, .backup: 1
            case .filters: 3
            case .memories: 6
            case .settings: 11
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case loading(Step, stepFraction: Double)
        case finished
        case failed(Step, String)
    }

    private(set) var phase: Phase = .idle
    /// The loading screen is showing. The load itself continues if the user hides it.
    var isOverlayVisible = false

    // Loaded data
    private(set) var memories: [MemoryChannel]?
    private(set) var settings: SettingsBackup?
    private(set) var clockSupported: Bool?
    private(set) var radioTime: String?
    private(set) var backupNote: String?

    private let connection: RadioConnection
    private let backups: BackupStore
    private var task: Task<Void, Never>?

    init(connection: RadioConnection, backups: BackupStore) {
        self.connection = connection
        self.backups = backups
    }

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    /// 0…1 across all steps.
    var overallFraction: Double {
        let total = steps.map(\.weight).reduce(0, +)
        func done(before step: Step) -> Double { steps.filter { $0.rawValue < step.rawValue }.map(\.weight).reduce(0, +) }
        switch phase {
        case .idle: return 0
        case .finished: return 1
        case let .loading(step, f): return (done(before: step) + step.weight * f) / total
        case let .failed(step, _): return done(before: step) / total
        }
    }

    func status(of step: Step) -> StepStatus {
        switch phase {
        case .idle: return .pending
        case .finished: return .done
        case let .loading(current, _):
            return step.rawValue < current.rawValue ? .done : step == current ? .active : .pending
        case let .failed(current, _):
            return step.rawValue < current.rawValue ? .done : step == current ? .failed : .pending
        }
    }

    enum StepStatus { case pending, active, done, failed }

    // MARK: Lifecycle

    /// Connects and then loads everything.
    func connectAndLoad() async {
        await connection.connect()
        guard connection.isConnected else { return }
        start()
    }

    func start() {
        task?.cancel()
        reset(keepOverlay: false)
        let full = AppPreferences.loadEverythingOnConnect
        steps = full ? Step.allCases : Self.quickSteps
        isOverlayVisible = full && AppPreferences.showLoadingScreen
        task = Task { await run(from: .radioState) }
    }

    /// Steps run on connect. Memories, settings and the automatic backup only run when
    /// "Read everything when connecting" is on in Preferences.
    private(set) var steps: [Step] = RadioLoader.quickSteps
    private static let quickSteps: [Step] = [.radioState, .filters, .clock]

    func retry() {
        guard case let .failed(step, _) = phase else { return }
        task = Task { await run(from: step) }
    }

    func disconnect() {
        task?.cancel()
        connection.disconnect()
        reset(keepOverlay: false)
    }

    // MARK: Features push fresh data back so the cache stays current

    func updateMemories(_ channels: [MemoryChannel]) { memories = channels }
    func updateSettings(_ backup: SettingsBackup) { settings = backup }
    func updateRadioTime(_ time: String) { radioTime = time; clockSupported = true }

    // MARK: Private

    private func reset(keepOverlay: Bool) {
        phase = .idle
        memories = nil
        settings = nil
        clockSupported = nil
        radioTime = nil
        backupNote = nil
        if !keepOverlay { isOverlayVisible = false }
    }

    private func run(from first: Step) async {
        for step in steps where step.rawValue >= first.rawValue {
            guard !Task.isCancelled, connection.isConnected, let cat = connection.cat else {
                // Disconnected mid-load (e.g. Firmware took the port): quietly stop.
                reset(keepOverlay: false)
                return
            }
            phase = .loading(step, stepFraction: 0)
            do {
                try await perform(step, cat: cat)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(step, error.localizedDescription)
                isOverlayVisible = true
                return
            }
        }
        phase = .finished
        isOverlayVisible = false
    }

    private func perform(_ step: Step, cat: KenwoodCAT) async throws {
        switch step {
        case .radioState:
            connection.adopt(state: try await cat.readState())

        case .filters:
            await connection.loadFilterTable()

        case .clock:
            do {
                radioTime = try await cat.radioTime()
                clockSupported = true
            } catch TimeSyncError.unsupported {
                clockSupported = false
            }

        case .memories:
            let range = TX500Protocol.Memory.channelRange
            var read: [MemoryChannel] = []
            for number in range {
                try Task.checkCancellation()
                read.append(try await cat.memoryChannel(number))
                phase = .loading(step, stepFraction: Double(read.count) / Double(range.count))
            }
            memories = read

        case .settings:
            let count = TX500Protocol.Settings.byteCount
            var bytes: [UInt8] = []
            bytes.reserveCapacity(count)
            while bytes.count < count {
                try Task.checkCancellation()
                let batch = min(TX500Protocol.Settings.readBatchSize, count - bytes.count)
                bytes += try await cat.readSettings(startIndex: bytes.count, count: batch)
                phase = .loading(step, stepFraction: Double(bytes.count) / Double(count))
            }
            settings = try SettingsBackup(bytes: bytes)

        case .backup:
            try saveAutomaticBackup()
        }
    }

    private func saveAutomaticBackup() throws {
        guard let settings else { return }
        switch AppPreferences.autoBackupPolicy {
        case .never:
            backupNote = nil
        case .always:
            try backups.save(settings)
            backupNote = "Backup saved."
        case .whenChanged:
            if let latest = backups.latest, let previous = try? backups.load(latest), previous == settings {
                backupNote = "Settings unchanged since your last backup."
            } else {
                try backups.save(settings)
                backupNote = "Settings changed. New backup saved."
            }
        }
    }
}
