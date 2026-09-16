import SwiftUI
import TX500Kit

/// Live front panel: frequency, mode, S-meter and the common controls.
struct RadioView: View {
    @Environment(RadioConnection.self) private var connection
    @State private var frequencyEntry = ""
    @State private var powerEntry = Levels.powerPercent.displayRange.upperBound

    private typealias Levels = TX500Protocol.CAT.Levels

    private var state: RigState { connection.state }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if case let .failed(message) = connection.status {
                    ErrorBanner(message: message) { connection.disconnect() }
                }
                if let error = connection.lastError {
                    ErrorBanner(message: error) { connection.lastError = nil }
                }

                if connection.isConnected {
                    displayCard
                    controlsCard
                    levelsCard
                } else {
                    NotConnectedView()
                }
            }
            .padding(Theme.Spacing.xl)
        }
    }

    // MARK: Cards

    private var displayCard: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.lg) {
                Text(state.frequencyHz.map(FrequencyFormat.dotted) ?? Placeholder.unknown)
                    .font(Theme.Typography.frequency)
                    .contentTransition(.numericText())
                Text(state.mode?.label ?? Placeholder.unknown)
                    .font(Theme.Typography.value)
                    .foregroundStyle(Theme.Palette.accent)
                Spacer()
                StatusBadge(text: state.transmitting ? "TX" : "RX",
                            color: state.transmitting ? Theme.Palette.transmit : Theme.Palette.receive)
            }
            // Five values in a fixed row need far more than the 490pt available at the minimum
            // window size, so they wrap instead of truncating — same layout the badges use.
            FlowLayout(spacing: Theme.Spacing.xl, lineSpacing: Theme.Spacing.md) {
                LabeledValue(label: "VFO B", value: state.vfoB.map(FrequencyFormat.dotted))
                LabeledValue(label: "Supply", value: state.supplyVolts.map { String(format: "%.1f V", $0) })
                LabeledValue(label: "AGC", value: state.agcTimeConstant.map(String.init))
                LabeledValue(label: "RX Filter", value: filterDescription)
                LabeledValue(label: "TX Filter", value: state.txFilterPreset.map { "FIL\($0 + 1)" })
            }
            badgeRow
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("S-METER").font(Theme.Typography.label).foregroundStyle(Theme.Palette.secondaryText)
                MeterBar(value: Double(state.sMeter ?? 0), maximum: Double(TX500Protocol.CAT.sMeterFullScale))
            }
        }
    }

    private var controlsCard: some View {
        Card("Controls") {
            HStack(spacing: Theme.Spacing.md) {
                TextField("Frequency (e.g. 14.074)", text: $frequencyEntry)
                    .frame(width: Theme.Metrics.fieldWidth)
                    .onSubmit(applyFrequency)
                Button("Set VFO A", action: applyFrequency)
                    .disabled(FrequencyFormat.parse(frequencyEntry) == nil)
            }

            Picker("Mode", selection: modeBinding) {
                ForEach(OperatingMode.allCases) { mode in
                    Text(mode.label).tag(Optional(mode))
                }
            }
            .pickerStyle(.segmented)

            Stepper(value: $powerEntry, in: Levels.powerPercent.displayRange, step: Levels.powerStep) {
                Text("Power: \(Levels.powerPercent.formatted(powerEntry))")
            }
            .onChange(of: powerEntry) { _, percent in
                guard percent != state.powerPercent else { return }
                Task { await connection.perform { try await $0.setPower(percent: percent) } }
            }
        }
        .onAppear { powerEntry = state.powerPercent ?? powerEntry }
        .onChange(of: state.powerPercent) { _, percent in
            if let percent { powerEntry = percent }
        }
    }

    private var levelsCard: some View {
        Card("Levels") {
            HStack(spacing: Theme.Spacing.xl) {
                LabeledValue(label: "Power", value: state.powerPercent.map(Levels.powerPercent.formatted))
                LabeledValue(label: "AF Gain", value: state.afGain.map(Levels.afGain.formatted))
                LabeledValue(label: "RF Gain", value: state.rfGainDB.map(Levels.rfGain.formatted))
                LabeledValue(label: "Squelch", value: state.squelch.map(String.init))
                LabeledValue(label: "Keyer", value: state.keyerCPM.map(Levels.keyerSpeed.formatted))
                LabeledValue(label: "VOX", value: state.vox.map { $0 ? "On" : "Off" })
                LabeledValue(label: "NB", value: state.noiseBlanker.map { $0 ? "On" : "Off" })
                LabeledValue(label: "NR", value: state.noiseReduction.map { $0 ? "On" : "Off" })
            }
        }
    }

    private var badgeRow: some View {
        FlowLayout {
            FunctionBadge(title: "VOX", isOn: state.vox)
            FunctionBadge(title: "MON", isOn: state.monitorOn, detail: state.monitorLevel.map(String.init))
            FunctionBadge(title: "COMP", isOn: state.compressorOn)
            FunctionBadge(title: "PRE", isOn: state.preampOn)
            FunctionBadge(title: "ATT", isOn: state.attenuatorOn)
            FunctionBadge(title: "NB", isOn: state.noiseBlanker)
            FunctionBadge(title: "NR", isOn: state.noiseReduction)
            FunctionBadge(title: "NOTCH", isOn: state.notchOn)
            FunctionBadge(title: "SPLIT", isOn: state.splitOn)
            FunctionBadge(title: "RIT", isOn: state.ritOn)
            FunctionBadge(title: "XIT", isOn: state.xitOn)
            FunctionBadge(title: "LOCK", isOn: state.locked)
            // The filter preset and its bandwidth are already shown as "RX Filter" above.
        }
    }

    private var filterWidth: String? {
        guard let preset = state.rxFilterPreset, let mode = state.mode,
              let hz = connection.filterTable?.bandwidth(mode: mode, preset: preset) else { return nil }
        return FilterTable.format(hz)
    }

    private var filterDescription: String? {
        state.rxFilterPreset.map { preset in
            ["FIL\(preset + 1)", filterWidth].compactMap { $0 }.joined(separator: " · ")
        }
    }

    // MARK: Actions

    private var modeBinding: Binding<OperatingMode?> {
        Binding(
            get: { state.mode },
            set: { newMode in
                guard let newMode else { return }
                Task { await connection.perform { try await $0.setMode(newMode) } }
            }
        )
    }

    private func applyFrequency() {
        guard let hz = FrequencyFormat.parse(frequencyEntry) else { return }
        Task { await connection.perform { try await $0.setFrequency(hz) } }
        frequencyEntry = ""
    }
}
