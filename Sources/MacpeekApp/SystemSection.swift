import AppKit
import MacpeekCore
import SwiftUI

struct SystemSection: View {
    let model: AppModel
    @State private var byMemory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(icon: "cpu", label: "CPU", value: Format.percent(model.cpu.total))
            Sparkline(values: model.cpuHistory.values, capacity: model.cpuHistory.capacity)
                .fill(.blue.gradient)
                .frame(height: 28)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 4))
            InfoRow(icon: "memorychip", label: "Memory", value: memoryText,
                    valueColor: model.memory?.pressure == .critical ? .red : .primary)
            if let memory = model.memory {
                ProgressView(value: memory.fraction)
                    .tint(pressureColor(memory.pressure))
            }
            Picker("Sort", selection: $byMemory) {
                Text("Top CPU").tag(false)
                Text("Top Memory").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if topApps.isEmpty {
                Text("Measuring…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(topApps) { app in
                Button { openActivityMonitor() } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: AppIcons.icon(for: app.bundlePath))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(byMemory ? Format.memory(app.memory) : String(format: "%.1f%%", app.cpu))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var topApps: [ProcessUsage] {
        let sorted = model.apps.sorted { byMemory ? $0.memory > $1.memory : $0.cpu > $1.cpu }
        return Array(sorted.prefix(5))
    }

    private var memoryText: String {
        guard let memory = model.memory else { return "—" }
        return "\(Format.memory(memory.used)) of \(Format.memory(memory.total))"
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}
