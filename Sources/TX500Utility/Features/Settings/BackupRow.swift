import SwiftUI
import TX500Kit

/// One backup in the Settings Backups list. The same actions appear as buttons and in the context menu.
struct BackupRow: View {
    let entry: BackupStore.Entry
    let otherEntries: [BackupStore.Entry]
    let matchesRadio: Bool
    let canRestore: Bool
    let onView: () -> Void
    let onCompare: (BackupStore.Entry) -> Void
    let onExport: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        .font(Theme.Typography.body)
                    StatusBadge(text: entry.source == .radio ? "Radio" : "Imported",
                                color: entry.source == .radio ? Theme.Palette.sourceRadio : Theme.Palette.sourceImported)
                    if matchesRadio {
                        StatusBadge(text: "Matches radio", color: Theme.Palette.success)
                    }
                }
                Text(entry.displayName ?? entry.url.lastPathComponent)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Spacer()
            Button("View", action: onView)
            compareMenu
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions")
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .contextMenu { actions }
    }

    private var compareMenu: some View {
        Menu("Compare") {
            if otherEntries.isEmpty {
                Text("No other backups")
            }
            ForEach(otherEntries) { other in
                Button(other.date.formatted(date: .abbreviated, time: .standard)) { onCompare(other) }
            }
        }
        .fixedSize()
        .disabled(otherEntries.isEmpty)
        .help("Open this backup with the differences from another backup highlighted")
    }

    @ViewBuilder
    private var actions: some View {
        Button("View", action: onView)
        Button("Export Copy…", action: onExport)
        Button("Show in Finder") { FilePanels.reveal(entry.url) }
        Divider()
        Button("Restore to Radio…", action: onRestore)
            .disabled(!canRestore)
        Button("Delete…", role: .destructive, action: onDelete)
    }
}
