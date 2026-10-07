import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Network speed", isOn: $model.showNetwork)
                Toggle("Disk space", isOn: $model.showDisk)
                Toggle("VPN shield", isOn: $model.showVPN)
                Picker("Update every", selection: $model.interval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
            }
            Section {
                Toggle("VPN disconnects", isOn: $model.alertVPN)
                Toggle("Public IP changes while on VPN", isOn: $model.alertIPChange)
                Toggle("Memory runs low", isOn: $model.alertMemory)
                Toggle("Mac is throttling from heat", isOn: $model.alertThermal)
            } header: {
                Text("Notify Me When")
            } footer: {
                Text("Slower updates use less energy.")
                    .foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Check for updates daily", isOn: Bindable(model.updater).automatic)
                HStack {
                    Button("Check Now") { Task { await model.updater.check(manual: true) } }
                    Text(updateStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var updateStatus: String {
        switch model.updater.status {
        case .idle: model.updater.available.map { "Version \($0.version) is available." } ?? ""
        case .checking: "Checking…"
        case .upToDate: "You're up to date."
        case .installing: "Installing…"
        case .checkFailed(let message), .failed(let message): message
        }
    }
}
