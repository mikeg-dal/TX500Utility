import SwiftUI
import TX500Kit

/// App preferences (⌘,). Not to be confused with the radio's own settings.
@MainActor
struct PreferencesView: View {
    @AppStorage(AppPreferences.Key.autoBackupPolicy) private var autoBackup = AppPreferences.defaultAutoBackupPolicy
    @AppStorage(AppPreferences.Key.showLoadingScreen) private var showLoadingScreen = AppPreferences.defaultShowLoadingScreen
    @AppStorage(AppPreferences.Key.loadEverythingOnConnect) private var loadEverything = AppPreferences.defaultLoadEverythingOnConnect
    @AppStorage(AppPreferences.Key.catBaudRate) private var baudRate = TX500Protocol.CAT.baudRate

    var body: some View {
        Form {
            Section("When Connecting") {
                Toggle("Read memories and all menu settings when connecting", isOn: $loadEverything)
                Toggle("Show loading screen while reading", isOn: $showLoadingScreen)
                    .disabled(!loadEverything)
                Text(loadEverything
                     ? "After connecting the app reads status, memories and all menu settings (about 20 seconds) so every section is ready to browse."
                     : "Connecting reads status, filters and clock only. Memories and settings are read when you open them and press Read.")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            Section("Serial Port") {
                Picker("Speed", selection: $baudRate) {
                    ForEach(TX500Protocol.CAT.standardBaudRates, id: \.self) { rate in
                        Text(rate == TX500Protocol.CAT.baudRate ? "\(rate) (radio default)" : "\(rate)")
                            .tag(rate)
                    }
                }
                if baudRate == TX500Protocol.CAT.baudRate {
                    Text("The TX-500's CAT port runs at 9600 8-N-1 and has no speed setting of its own. Change this only if something sits between the Mac and the radio — a serial bridge or an adapter — that needs a different rate.")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.secondaryText)
                } else {
                    Label("The radio itself will not answer at \(baudRate). Reconnect for this to take effect, and set it back to \(TX500Protocol.CAT.baudRate) if the radio stops responding.",
                          systemImage: "exclamationmark.triangle")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.warning)
                }
                Text("Firmware updates always use \(TX500Protocol.Bootloader.baudRate) baud, whatever this is set to — the loader fixes that speed.")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            Section("Automatic Settings Backup (after reading all settings)") {
                Picker("Save a backup after connecting", selection: $autoBackup) {
                    ForEach(AutoBackupPolicy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(autoBackup.detail)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        .formStyle(.grouped)
        .frame(width: Theme.Metrics.preferencesWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}
