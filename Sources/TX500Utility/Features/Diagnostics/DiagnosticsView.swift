import SwiftUI
import TX500Kit

/// Command probe table and a raw CAT console.
struct DiagnosticsView: View {
    @Environment(RadioConnection.self) private var connection
    @State private var probeRows: [ProbeRow] = []
    @State private var isProbing = false
    @State private var consoleInput = ""
    @State private var consoleLog: [String] = []

    struct ProbeRow: Identifiable {
        let id = UUID()
        let command: String
        let result: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if !connection.isConnected {
                    NotConnectedView(detail: "Connect to the radio to run diagnostics.")
                } else {
                    probeCard
                    consoleCard
                }
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private var probeCard: some View {
        Card("Command Support") {
            HStack {
                Text("Sends read-only queries and reports which ones the radio answers.")
                    .foregroundStyle(Theme.Palette.secondaryText)
                Spacer()
                Button(isProbing ? "Probing…" : "Run Probe", action: runProbe)
                    .disabled(isProbing)
            }
            if !probeRows.isEmpty {
                Table(probeRows) {
                    TableColumn("Command", value: \.command)
                    TableColumn("Response", value: \.result)
                }
                .font(Theme.Typography.mono)
                .frame(minHeight: Theme.Metrics.consoleMinHeight)
            }
        }
    }

    private var consoleCard: some View {
        Card("Raw Console") {
            ScrollView {
                Text(consoleLog.joined(separator: "\n"))
                    .font(Theme.Typography.monoSmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: Theme.Metrics.consoleMinHeight)
            HStack {
                TextField("CAT command, e.g. FA;", text: $consoleInput)
                    .font(Theme.Typography.mono)
                    .onSubmit(sendConsole)
                Button("Send", action: sendConsole)
                    .disabled(consoleInput.isEmpty)
            }
            Text("Raw commands are sent as typed. Commands that start transmitting (TX;, CG010–CG100) are blocked here.")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.warning)
        }
    }

    private func runProbe() {
        isProbing = true
        Task {
            await connection.perform { cat in
                let results = try await cat.probe(KenwoodCAT.probeCommands)
                probeRows = results.map { cmd, result in
                    switch result {
                    case let .answered(r): ProbeRow(command: cmd, result: r)
                    case .echoed: ProbeRow(command: cmd, result: "unsupported (echoed)")
                    case .silent: ProbeRow(command: cmd, result: "no answer")
                    }
                }
            }
            isProbing = false
        }
    }

    private func sendConsole() {
        let command = consoleInput
        consoleInput = ""
        Task {
            await connection.perform { cat in
                let response = try await cat.raw(command)
                consoleLog.append("> \(command)")
                consoleLog.append("< \(response.isEmpty ? "(no answer)" : response)")
            }
        }
    }
}
