import Foundation
import Observation
import TX500Kit

/// App-wide owner of the serial port and CAT session. Features read `state` and call
/// `perform` for commands; nothing else opens the port while CAT is connected.
@MainActor
@Observable
final class RadioConnection {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected(id: String)
        case failed(String)
    }

    private(set) var ports: [SerialPortInfo] = []
    var selectedPortPath: String?
    private(set) var status: Status = .disconnected
    private(set) var state = RigState()
    /// Filter passbands from the settings table; loaded once after connecting.
    private(set) var filterTable: FilterTable?
    var lastError: String?

    private var port: SerialPort?
    private(set) var cat: KenwoodCAT?
    private var pollTask: Task<Void, Never>?

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    init() {
        refreshPorts()
    }

    func refreshPorts() {
        ports = PortDiscovery.availablePorts()
        if selectedPortPath == nil || !ports.contains(where: { $0.path == selectedPortPath }) {
            selectedPortPath = ports.first(where: \.isLikelyTX500Cable)?.path ?? ports.first?.path
        }
    }

    func connect() async {
        guard let path = selectedPortPath else {
            status = .failed("Select a serial port first")
            return
        }
        disconnect()
        status = .connecting
        let port = SerialPort(path: path, baudRate: AppPreferences.catBaudRate)
        do {
            try port.open()
            let cat = KenwoodCAT(transport: port)
            let id = try await cat.identify()
            self.port = port
            self.cat = cat
            state = try await cat.readState()
            status = .connected(id: id)
            startPolling()
        } catch {
            port.close()
            status = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        // Closing deliberately: anything the teardown reports is noise, and a stale banner would
        // otherwise follow the user to the next page.
        lastError = nil
        port?.close()
        port = nil
        cat = nil
        state = RigState()
        filterTable = nil
        status = .disconnected
    }

    /// Runs a CAT operation, reporting failures through `lastError`, then refreshes state.
    func perform(_ operation: @escaping (KenwoodCAT) async throws -> Void) async {
        guard let cat else { return }
        do {
            try await operation(cat)
            state = try await cat.readState()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Replaces the displayed state with a fresh read (used by the connect-time loader).
    func adopt(state: RigState) {
        self.state = state
    }

    /// Re-reads the filter passbands (e.g. after changing a filter preset's width on the radio).
    func loadFilterTable() async {
        guard let cat else { return }
        filterTable = try? await cat.readFilterTable()
    }

    /// Temporarily stops polling and closes the port so another component (e.g. the bootloader)
    /// can use it exclusively. Returns the path that was in use.
    func releasePort() -> String? {
        let path = selectedPortPath
        disconnect()
        return path
    }

    /// Consecutive failed polls tolerated before the connection is dropped. Each failure already
    /// waits out its own read timeout, so this is a couple of seconds rather than milliseconds.
    private static let failuresBeforeDisconnect = 5
    private static let lostRadioMessage = "The radio stopped answering. Check that it is powered on and the cable is connected."

    private func startPolling() {
        pollTask = Task { [weak self] in
            var tick = 0
            var consecutiveFailures = 0
            while !Task.isCancelled {
                guard let self, let cat = self.cat else { return }
                do {
                    if tick % TX500Protocol.CAT.fullRefreshEveryPolls == 0 {
                        self.state = try await cat.readState()
                    } else {
                        var s = self.state
                        try await cat.readLive(into: &s)
                        self.state = s
                    }
                    consecutiveFailures = 0
                } catch {
                    // Disconnecting cancels this task and closes the port, but a read already in
                    // flight still resumes and throws ("Bad file descriptor"). That is the
                    // disconnect working, not something the user needs to see — and it used to
                    // surface later, on whichever page they opened next.
                    guard !Task.isCancelled, self.port != nil else { return }

                    // A radio switched off mid-session answers nothing, and polling a dead port
                    // forever left the app looking connected. Give up after a few failures in a
                    // row rather than the first: the radio also goes quiet for a moment when its
                    // front panel is busy, which is not a reason to tear down a working session.
                    consecutiveFailures += 1
                    if consecutiveFailures >= Self.failuresBeforeDisconnect {
                        self.disconnect()
                        self.status = .failed(Self.lostRadioMessage)
                        return
                    }
                    self.lastError = error.localizedDescription
                }
                tick += 1
                try? await Task.sleep(for: TX500Protocol.CAT.livePollInterval)
            }
        }
    }
}
