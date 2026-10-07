import AppKit
import SwiftUI

struct WelcomeView: View {
    let model: AppModel
    let done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            VStack(spacing: 6) {
                Text("Welcome to Macpeek")
                    .font(.title2.bold())
                Text("Your Mac at a glance, right from the menu bar.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("lock.shield", "Privacy", "VPN status, your public IP and leak checks.")
                feature("cpu", "System", "CPU, memory, network and the apps using them.")
                feature("leaf", "Light", "Uses almost no energy, so it's fine to leave running.")
                feature("keyboard", "Shortcut", "Press \(model.shortcut?.display ?? "the shortcut") to open it from anywhere.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Open Macpeek at login", isOn: Binding(get: { model.openAtLogin },
                                                              set: { model.setOpenAtLogin($0) }))
                if !model.notificationsAllowed {
                    HStack {
                        Text("Get told when your VPN drops.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow Notifications") { Task { await model.allowNotifications() } }
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            Button(action: done) {
                Text("Get Started").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .padding(.top, 8)
        .frame(width: 400)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
