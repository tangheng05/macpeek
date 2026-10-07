import AppKit
import MacpeekCore
import SwiftUI

struct SystemSection: View {
    let model: AppModel
    @State private var sort = Sort.cpu
    private static let rows = 5

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
                if Self.hasEnergy { Text("Energy").tag(Sort.energy) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            let apps = topApps
            ForEach(0..<Self.rows, id: \.self) { index in
                if index < apps.count {
                    row(apps[index])
                } else if index == 0 {
                    Text("Measuring…")
                        .foregroundStyle(.secondary)
                        .frame(height: 16)
                } else {
                    Color.clear.frame(height: 16)
                }
            }
        }
    }

    private func row(_ app: ProcessUsage) -> some View {
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

    private var topApps: [ProcessUsage] {
        let sorted = model.apps.sorted {
            switch sort {
            case .cpu: $0.cpu > $1.cpu
            case .memory: $0.memory > $1.memory
            case .energy: $0.power > $1.power
            }
        }
        return Array(sorted.prefix(Self.rows))
    }

    /// Intel Macs don't count energy per process. Decided up front so the picker never changes
    /// shape: the first sample after opening reads zero for every app.
    #if arch(arm64)
    private static let hasEnergy = true
    #else
    private static let hasEnergy = false
    #endif

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
