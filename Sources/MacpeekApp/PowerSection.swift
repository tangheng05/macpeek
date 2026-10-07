import MacpeekCore
import SwiftUI

struct PowerSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let disk = model.disk {
                InfoRow(icon: "internaldrive", label: "Disk", value: "\(Format.bytes(disk.free)) free")
                ProgressView(value: disk.total == 0 ? 0 : Double(disk.used) / Double(disk.total))
            }
            if let power = model.power {
                InfoRow(icon: batteryIcon(power), label: "Battery", value: batteryText(power))
                if let watts = power.watts, watts > 0.05 {
                    InfoRow(icon: "bolt", label: power.charging ? "Charging at" : "Power Draw",
                            value: String(format: "%.1f W", watts))
                }
                if let health = power.health {
                    InfoRow(icon: "heart", label: "Health", value: "\(health)%" + (power.cycleCount.map { " · \($0) cycles" } ?? ""))
                }
                if let temperature = power.temperature {
                    InfoRow(icon: "thermometer.low", label: "Battery Temp", value: String(format: "%.1f °C", temperature))
                }
            }
            InfoRow(icon: "thermometer.medium", label: "Thermal", value: model.thermal.rawValue.capitalized,
                    valueColor: model.thermal.isThrottling ? .orange : .primary)
        }
    }

    private func batteryText(_ power: PowerInfo) -> String {
        var text = "\(power.percent)%"
        if let minutes = power.minutesLeft {
            text += power.charging ? " · full in \(Format.duration(minutes: minutes))" : " · \(Format.duration(minutes: minutes)) left"
        } else if power.pluggedIn {
            text += power.charging ? " · charging" : " · plugged in"
        }
        return text
    }

    private func batteryIcon(_ power: PowerInfo) -> String {
        if power.charging { return "battery.100percent.bolt" }
        switch power.percent {
        case 75...: return "battery.100percent"
        case 50..<75: return "battery.75percent"
        case 25..<50: return "battery.50percent"
        case 10..<25: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
