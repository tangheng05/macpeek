import AppKit
import MacpeekCore
import SwiftUI

struct SystemSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("System")
            GaugeRow(label: "CPU", value: Format.percent(model.cpu.total)) {
                Sparkline(values: model.cpuHistory.values, capacity: model.cpuHistory.capacity)
                    .fill(Color.accentColor.gradient)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 3))
            }
            if let memory = model.memory {
                GaugeRow(label: "Memory", value: Format.memory(memory.used)) {
                    Meter(value: memory.pressureFraction, color: pressureColor(memory.pressure))
                }
                .help("\(Format.memory(memory.used)) of \(Format.memory(memory.total)) used. The bar is memory pressure, "
                      + "\(Format.percent(memory.pressureFraction)): how hard macOS is working to free up memory.")
            }
            if let disk = model.disk {
                let used = disk.total == 0 ? 0 : Double(disk.used) / Double(disk.total)
                GaugeRow(label: "Disk", value: "\(Format.bytes(disk.free)) free") {
                    Meter(value: used, color: used > 0.9 ? .orange : .gray)
                }
            }
            if model.thermal.isThrottling {
                ValueRow(label: "Heat", value: "Slowing down to cool", valueColor: .orange)
            }
        }
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}

/// Label, a live gauge and its value, on columns shared by every row so the gauges line up.
private struct GaugeRow<Gauge: View>: View {
    let label: String
    let value: String
    @ViewBuilder var gauge: Gauge

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 54, alignment: .leading)
            gauge
                .frame(height: 16)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
        }
    }
}

struct TopAppsSection: View {
    let model: AppModel
    @State private var sort = Sort.cpu
    private static let rows = 5

    private enum Sort: CaseIterable {
        case cpu, memory, energy

        var title: String {
            switch self {
            case .cpu: "CPU"
            case .memory: "Memory"
            case .energy: "Energy"
            }
        }
    }

    /// Intel Macs don't count energy per process. Decided up front so the menu never changes
    /// shape: the first sample after opening reads zero for every app.
    #if arch(arm64)
    private static let sorts = Sort.allCases
    #else
    private static let sorts: [Sort] = [.cpu, .memory]
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Top apps") {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(Self.sorts, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text("By \(sort.title)")
                        .font(.subheadline)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .fixedSize()
                .help("Sort by")
            }
            let apps = topApps
            ForEach(0..<Self.rows, id: \.self) { index in
                if index < apps.count {
                    Button { openActivityMonitor() } label: {
                        AppRow(icon: AppIcons.icon(for: apps[index].bundlePath), name: apps[index].name, value: value(apps[index]))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Open Activity Monitor")
                } else if index == 0 {
                    Text("Measuring…")
                        .foregroundStyle(.secondary)
                        .frame(height: AppRow.height)
                } else {
                    Color.clear.frame(height: AppRow.height)
                }
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
        return Array(sorted.prefix(Self.rows))
    }

    private func value(_ app: ProcessUsage) -> String {
        switch sort {
        case .cpu: String(format: "%.1f%%", app.cpu)
        case .memory: Format.memory(app.memory)
        case .energy: String(format: "%.2f W", app.power)
        }
    }

    private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}
