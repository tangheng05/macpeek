import AppKit
import MacpeekCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                LabeledContent("Open Macpeek") {
                    ShortcutRecorder(model: model)
                }
            } header: {
                Text("General")
            } footer: {
                if model.shortcutTaken {
                    Text("Another app already uses this shortcut. Pick a different one.")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Network speed", isOn: $model.showNetwork)
                Toggle("Disk space", isOn: $model.showDisk)
                Toggle("Colored graphs", isOn: $model.coloredMenuBar)
                Picker("Update every", selection: $model.interval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Without color, Macpeek matches the system icons. Slower updates use less energy.")
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Toggle("Test DNS with an outside service", isOn: $model.activeDNSTest)
                Text("Only when you run Full Test while on a VPN. Sends one lookup to ip-api.com.")
                    .foregroundStyle(.secondary)
            }
            Section {
                if !model.notificationsAllowed {
                    LabeledContent("Notifications are off") {
                        Button("Allow…") { Task { await model.allowNotifications() } }
                    }
                }
                Toggle("VPN disconnects", isOn: $model.alertVPN)
                Toggle("Public IP changes while on VPN", isOn: $model.alertIPChange)
                Toggle("Joining open Wi-Fi without VPN", isOn: $model.alertOpenWiFi)
                Toggle("Memory runs low", isOn: $model.alertMemory)
                Toggle("Mac is throttling from heat", isOn: $model.alertThermal)
                if model.power != nil {
                    Picker("Battery charges to", selection: $model.chargeLimit) {
                        Text("Off").tag(0)
                        Text("80%").tag(80)
                        Text("85%").tag(85)
                        Text("90%").tag(90)
                    }
                }
            } header: {
                Text("Notify Me When")
            }
            Section("Updates") {
                Toggle("Check for updates daily", isOn: Bindable(model.updater).automatic)
                LabeledContent("Version \(model.updater.currentVersion)") {
                    Button("Check Now") { Task { await model.updater.check(manual: true) } }
                        .disabled(model.updater.status == .checking || model.updater.status == .installing)
                }
                if !updateStatus.isEmpty {
                    Text(updateStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .task { await model.refreshNotificationStatus() }
    }

    private var updateStatus: String {
        switch model.updater.status {
        case .idle:
            model.updater.available.map {
                model.updater.viaHomebrew
                    ? "Version \($0.version) is available. Run \(Updater.brewCommand) in Terminal."
                    : "Version \($0.version) is available."
            } ?? ""
        case .copiedCommand: "Copied. Paste it in Terminal to update."
        case .checking: "Checking…"
        case .upToDate: "You're up to date."
        case .installing: "Installing…"
        case .checkFailed(let message), .failed(let message): message
        }
    }
}

/// Click, then press the new combination. Esc cancels.
private struct ShortcutRecorder: View {
    @Bindable var model: AppModel
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .frame(minWidth: 96)
                    .foregroundStyle(model.recordingShortcut ? .secondary : .primary)
            }
            if model.shortcut != nil, !model.recordingShortcut {
                Button {
                    model.shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Turn off the shortcut")
                .accessibilityLabel("Turn off the shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if model.recordingShortcut { return hint ?? "Press keys…" }
        return model.shortcut?.display ?? "Record Shortcut"
    }

    private func toggleRecording() {
        model.recordingShortcut ? stop() : start()
    }

    private func start() {
        model.recordingShortcut = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        model.recordingShortcut = false
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 { return stop() }
        let flags = event.modifierFlags
        let combo = KeyCombo(keyCode: UInt32(event.keyCode), key: keyName(event),
                             command: flags.contains(.command), option: flags.contains(.option),
                             control: flags.contains(.control), shift: flags.contains(.shift))
        guard combo.isValid else {
            hint = "Add ⌘, ⌥ or ⌃"
            return
        }
        model.shortcut = combo
        stop()
    }

    private func keyName(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let key = event.charactersIgnoringModifiers ?? ""
            return key.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0.properties.numericType != nil
                || CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0) } ? key : ""
        }
    }
}
