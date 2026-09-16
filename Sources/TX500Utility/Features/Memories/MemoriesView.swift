import SwiftUI
import TX500Kit

struct MemoriesView: View {
    @Environment(RadioConnection.self) private var connection
    @Environment(RadioLoader.self) private var loader
    @State private var model = MemoriesModel()
    @State private var confirmWrite = false
    @State private var showEmpty = false
    /// Which row is being typed in. Owned here, not by the row, so that pressing a button can end
    /// editing first: on macOS clicking a button does not reliably take focus off a text field, so a
    /// frequency typed and then written straight away would never be parsed into the channel.
    @FocusState private var focusedChannel: Int?

    private var visibleChannels: [Binding<MemoryChannel>] {
        $model.channels.filter { showEmpty || !$0.wrappedValue.isEmpty }
    }

    var body: some View {
        SectionPage {
            if let message = model.errorMessage {
                ErrorBanner(message: message) { model.errorMessage = nil }
            }
            if !connection.isConnected {
                NotConnectedView()
            } else {
                actionsCard
                tableCard
            }
        }
        .onAppear { model.adoptIfFresh(loader.memories) }
        .onChange(of: loader.memories) { _, loaded in model.adoptIfFresh(loaded) }
    }

    private var actionsCard: some View {
        Card("Memory Channels") {
            HStack(spacing: Theme.Spacing.md) {
                Button("Read From Radio") { Task { await model.readFromRadio(connection: connection, loader: loader) } }
                Button("Write Changes…") { commitEdits(); confirmWrite = true }
                    .disabled(model.changedChannels.isEmpty)
                Divider().frame(height: Theme.Spacing.lg)
                Button("Import .mem…") { model.importFile() }
                Button("Export .mem…") { commitEdits(); model.exportFile() }
                Spacer()
                Toggle("Show empty", isOn: $showEmpty)
            }
            .disabled(model.isBusy)
            if let progress = model.progress {
                ProgressPanel(progress: progress)
            }
            if let status = model.statusMessage {
                Label(status, systemImage: "checkmark.circle").foregroundStyle(Theme.Palette.success)
            }
            Text("A memory holds a frequency, a mode and PRE/ATT — nothing else. Filters, noise reduction and gains are not stored per channel, so recalling a memory leaves them as the radio has them. PRE/ATT has no level because the radio's preamp and attenuator are fixed, not adjustable.")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text("Memory channels are not included in a settings backup (.set). Export a .mem file to keep them — the format is shared with Lab599's TRXMem.")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .confirmationDialog("Write \(model.changedChannels.count) channel(s) to the radio?", isPresented: $confirmWrite) {
            Button("Write", role: .destructive) { Task { await model.writeChanges(connection: connection, loader: loader) } }
        } message: {
            Text("Only channels that differ from what was read are written.")
        }
    }

    private var tableCard: some View {
        Card {
            if visibleChannels.isEmpty {
                Text(model.radioChannels == nil ? (loader.isLoading ? "Loading memory channels from the radio…" : "Read from the radio or import a file.") : "All channels are empty. Turn on “Show empty” to add one.")
                    .foregroundStyle(Theme.Palette.secondaryText)
            } else {
                // LazyVStack, not Grid: with "Show empty" on this is 100 rows, each carrying a text
                // field and two pop-up buttons. A Grid builds them all at once, which made the whole
                // app feel sluggish; lazily built rows only exist while they are on screen.
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        header("Mem").frame(width: Theme.Metrics.memoryChannelWidth, alignment: .leading)
                        header("Frequency").frame(width: Theme.Metrics.memoryFrequencyWidth, alignment: .leading)
                        header("Mode").frame(width: Theme.Metrics.memoryModeWidth, alignment: .leading)
                        header("PRE/ATT").frame(width: Theme.Metrics.memoryPreAttWidth, alignment: .leading)
                        Spacer()
                    }
                    Divider()
                    ForEach(visibleChannels, id: \.wrappedValue.id) { $channel in
                        MemoryRow(channel: $channel, focus: $focusedChannel) { model.clear(channel.number) }
                    }
                }
            }
        }
    }

    /// Ends editing so any half-typed frequency is parsed into its channel before we read them.
    private func commitEdits() {
        focusedChannel = nil
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.Typography.label).foregroundStyle(Theme.Palette.secondaryText)
    }

}

/// One editable grid row in the memory table.
private struct MemoryRow: View {
    @Binding var channel: MemoryChannel
    /// Shared with the table so an action elsewhere can end editing and force a commit.
    var focus: FocusState<Int?>.Binding
    let onClear: () -> Void
    @State private var frequencyText = ""

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(String(format: "%02d", channel.number))
                .font(Theme.Typography.mono)
                .frame(width: Theme.Metrics.memoryChannelWidth, alignment: .leading)
            TextField("MHz", text: $frequencyText)
                .font(Theme.Typography.mono)
                .frame(width: Theme.Metrics.memoryFrequencyWidth)
                .focused(focus, equals: channel.number)
                .onSubmit(commitFrequency)
                .onChange(of: focus.wrappedValue) { _, focused in
                    if focused != channel.number { commitFrequency() }   // typing finished in this row
                }
                .onAppear(perform: syncText)
                .onChange(of: channel.frequencyHz) { _, _ in syncText() }
            Picker("", selection: $channel.mode) {
                Text(Placeholder.unknown).tag(OperatingMode?.none)
                ForEach(OperatingMode.allCases) { Text($0.label).tag(Optional($0)) }
            }
            .labelsHidden()
            .frame(width: Theme.Metrics.memoryModeWidth)
            Picker("", selection: $channel.preAtt) {
                ForEach(PreAtt.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: Theme.Metrics.memoryPreAttWidth)
            Button(role: .destructive, action: onClear) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .frame(width: Theme.Metrics.memoryClearWidth)
                .help("Clear this channel")
                .disabled(channel.isEmpty)
            Spacer()
        }
    }

    private var formattedFrequency: String {
        channel.isEmpty ? "" : FrequencyFormat.dotted(channel.frequencyHz)
    }

    private func syncText() {
        frequencyText = formattedFrequency
    }

    private func commitFrequency() {
        // Every row observes the shared focus, so all of them are asked to commit whenever editing
        // ends anywhere. Only the row that was actually typed in has work to do.
        guard frequencyText != formattedFrequency else { return }
        if frequencyText.isEmpty {
            channel.frequencyHz = 0
        } else if let hz = FrequencyFormat.parse(frequencyText), TX500Protocol.CAT.frequencyRangeHz.contains(hz) {
            channel.frequencyHz = hz
            if channel.mode == nil { channel.mode = .usb }
        }
        syncText()
    }
}
