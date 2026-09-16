import SwiftUI
import TX500Kit

/// Sets the radio clock from the Mac (TM command; newer firmware only).
@MainActor
struct ClockView: View {
    @Environment(RadioConnection.self) private var connection
    @Environment(RadioLoader.self) private var loader
    @State private var support: Support = .unknown
    @State private var radioTime: String?
    @State private var errorMessage: String?

    enum Support { case unknown, supported, unsupported }

    var body: some View {
        SectionPage {
            if let errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
            if !connection.isConnected {
                NotConnectedView()
            } else {
                Card("Clock") {
                    HStack(spacing: Theme.Spacing.xl) {
                        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
                            LabeledValue(label: "Mac time", value: context.date.formatted(date: .omitted, time: .standard))
                        }
                        LabeledValue(label: "Radio time", value: radioTime)
                    }
                    switch support {
                    case .unknown:
                        ProgressView().controlSize(.small)
                    case .unsupported:
                        Label(TimeSyncError.unsupported.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Palette.warning)
                    case .supported:
                        Button("Sync Radio Clock to Mac") { Task { await sync() } }
                    }
                    Text("The clock is not part of a settings backup — restoring one never brings it back, so syncing is the only way to set it. It is kept separately in the radio and read with the CAT TM command.")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .task {
                    if let supported = loader.clockSupported {
                        support = supported ? .supported : .unsupported
                        radioTime = loader.radioTime
                    } else {
                        await checkSupport()
                    }
                }
            }
        }
    }

    private static let tick: TimeInterval = 1

    private func checkSupport() async {
        await connection.perform { cat in
            do {
                let time = try await cat.radioTime()
                await MainActor.run { radioTime = time; support = .supported }
            } catch TimeSyncError.unsupported {
                await MainActor.run { support = .unsupported }
            }
        }
        consumeError()
    }

    private func sync() async {
        await connection.perform { cat in
            let time = try await cat.syncClock()
            await MainActor.run {
                radioTime = time
                loader.updateRadioTime(time)
            }
        }
        consumeError()
    }

    private func consumeError() {
        if let e = connection.lastError {
            errorMessage = e
            connection.lastError = nil
        }
    }
}
