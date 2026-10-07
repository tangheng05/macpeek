import AppKit
import MacpeekCore
import SwiftUI

struct SystemSection: View {
    let model: AppModel
    @State private var sort = Sort.cpu

    private enum Sort {
        case cpu, memory, energy
    }

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
                Meter(value: memory.fraction, color: pressureColor(memory.pressure))
            }
            Picker("Sort", selection: $sort) {
                Text("CPU").tag(Sort.cpu)
                Text("Memory").tag(Sort.memory)
                if hasEnergy { Text("Energy").tag(Sort.energy) }
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
                        Text(value(app))
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
        let sorted = model.apps.sorted {
            switch sort {
            case .cpu: $0.cpu > $1.cpu
            case .memory: $0.memory > $1.memory
            case .energy: $0.power > $1.power
            }
        }
        return Array(sorted.prefix(5))
    }

    /// Intel Macs don't count energy per process, so the tab only shows when there's data.
    private var hasEnergy: Bool {
        model.apps.contains { $0.power > 0 }
    }

    private func value(_ app: ProcessUsage) -> String {
        switch sort {
        case .cpu: String(format: "%.1f%%", app.cpu)
        case .memory: Format.memory(app.memory)
        case .energy: String(format: "%.2f W", app.power)
        }
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
