import SwiftUI
import TX500Kit

/// Read-only, human-readable view of a settings backup: decoded fields and a spreadsheet of raw bytes.
struct SettingsViewerView: View {
    let request: SettingsViewerRequest

    @Environment(BackupStore.self) private var store
    @State private var model = SettingsViewerModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let message = model.errorMessage {
                ErrorBanner(message: message) { model.errorMessage = nil }
                    .padding(Theme.Spacing.md)
            }
            if model.backup != nil {
                decodedTable
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            legend
        }
        .frame(minWidth: Theme.Metrics.viewerMinWidth, minHeight: Theme.Metrics.viewerMinHeight)
        .navigationTitle(model.fileName)
        .onAppear {
            model.backupComparison = store.comparison
            model.load(request)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Menu(model.comparisonName.map { "Compare: \($0)" } ?? "Compare With…") {
                Button("None") { model.setComparison(nil) }
                Divider()
                ForEach(store.entries.filter { $0.url != request.fileURL }) { entry in
                    Button(entry.url.lastPathComponent) { model.setComparison(entry.url) }
                }
                Divider()
                Button("Other File…") {
                    model.setComparison(FilePanels.openFile(extension: TX500Protocol.Settings.fileExtension,
                                                            message: "Choose a settings file to compare"))
                }
            }
            .fixedSize()

            Toggle("Undecoded bytes", isOn: $model.showUndecoded)
            Toggle("Hide unchanging", isOn: $model.hideConstant)
                .disabled(!model.showUndecoded || model.backupComparison?.isUsable != true)
                .help("Hides undecoded bytes that hold the same value in every backup you have")
            Toggle("Only changed", isOn: $model.onlyChanged)
                .disabled(model.comparison == nil)
            TextField("Search", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: Theme.Metrics.fieldWidth)

            Spacer()
            Button("Export CSV…", action: exportCSV)
                .disabled(model.backup == nil)
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: Decoded

    private var decodedTable: some View {
        Table(model.rows) {
            TableColumn("Group") { Text($0.field.group).foregroundStyle(Theme.Palette.secondaryText) }
            TableColumn("Setting") { row in
                HStack(spacing: Theme.Spacing.xs) {
                    ConfidenceDot(confidence: row.field.confidence)
                    Text(row.field.name)
                }
                .help(evidence(for: row.field))
            }
            TableColumn("Value") { row in
                Text(row.value)
                    .font(Theme.Typography.mono)
                    .foregroundStyle(row.changed ? Theme.Palette.cellChanged : Theme.Palette.primaryText)
            }
            TableColumn("Previous") { row in
                Text(row.previousValue ?? "").font(Theme.Typography.mono).foregroundStyle(Theme.Palette.secondaryText)
            }
            TableColumn("Raw") { Text($0.hex).font(Theme.Typography.monoSmall) }
            TableColumn("Offset") { Text($0.offsetText).font(Theme.Typography.monoSmall) }
            TableColumn("CAT") { Text($0.addressText).font(Theme.Typography.monoSmall) }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(FieldConfidence.allCases, id: \.self) { c in
                HStack(spacing: Theme.Spacing.xs) {
                    ConfidenceDot(confidence: c)
                    Text(c.rawValue.capitalized)
                }
                .help(SettingsViewerView.meaning(of: c))
            }
            coverageText
            if model.constantUndecodedCount > 0, let backupComparison = model.backupComparison {
                Text("\(model.constantUndecodedCount) undecoded bytes are identical in all \(backupComparison.backupCount) of your backups")
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            if model.comparison != nil {
                Text("\(model.changedOffsets.count) bytes differ")
                    .foregroundStyle(Theme.Palette.cellChanged)
            }
            Spacer()
            Text("Read-only view of a saved backup. Export writes two files: the decoded settings, and the raw bytes as a grid.")
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .font(Theme.Typography.label)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    /// What the three dots mean, so the legend explains itself rather than needing a tooltip hunt.
    static func meaning(of confidence: FieldConfidence) -> String {
        switch confidence {
        case .confirmed: "Verified on a radio: this setting was changed and this byte moved with it."
        case .inferred: "Strongly suggested by the data — matching a documented default, or a single CAT reading — but not yet confirmed by changing it."
        case .unknown: "No known meaning yet. Most of these are bytes that are always zero."
        }
    }

    private var coverageText: some View {
        let c = SettingsLayout.coverage(of: model.fields)
        let decoded = c.confirmed + c.inferred
        return Text("Decoded \(decoded) of \(TX500Protocol.Settings.byteCount - c.reserved) bytes · \(c.confirmed) confirmed · \(c.inferred) inferred · \(c.reserved) reserved")
            .foregroundStyle(Theme.Palette.secondaryText)
    }

    private func evidence(for field: SettingsField) -> String {
        var parts = [field.confidence.rawValue.capitalized]
        if !field.note.isEmpty { parts.append(field.note) }
        if let updated = field.updated { parts.append("Updated \(updated.formatted(date: .abbreviated, time: .shortened))") }
        return parts.joined(separator: "\n")
    }

    private func exportCSV() {
        let base = (model.fileName as NSString).deletingPathExtension
        guard let url = FilePanels.saveFile(extension: SettingsViewerView.csvExtension, suggestedName: base + "." + SettingsViewerView.csvExtension,
                                            message: "Export settings as CSV") else { return }
        do {
            try model.csv().write(to: url, atomically: true, encoding: .utf8)
            // The raw grid is a different shape, so it goes in its own file beside the first one
            // rather than making the settings CSV unparseable.
            let grid = url.deletingPathExtension().appendingPathExtension(SettingsViewerView.rawSuffix)
            try model.hexGridCSV().write(to: grid, atomically: true, encoding: .utf8)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private static let csvExtension = "csv"
    /// Second file written beside the settings CSV, holding the raw 16-column byte grid.
    private static let rawSuffix = "raw.csv"
}
