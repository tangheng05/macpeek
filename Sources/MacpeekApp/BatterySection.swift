import MacpeekCore
import SwiftUI

struct BatterySection: View {
    let power: PowerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Battery")
            ValueRow(label: "Charge", value: charge)
            if let watts = power.watts, watts > 0.05 {
                ValueRow(label: power.charging ? "Charging at" : "Using", value: String(format: "%.1f W", watts))
            }
            if let health {
                ValueRow(label: "Health", value: health)
            }
        }
    }

    private var charge: String {
        let percent = "\(power.percent)%"
        if let minutes = power.minutesLeft {
            let time = Format.duration(minutes: minutes)
            return power.charging ? "\(percent), full in \(time)" : "\(percent), \(time) left"
        }
        if power.pluggedIn { return power.charging ? "\(percent), charging" : "\(percent), plugged in" }
        return percent
    }

    private var health: String? {
        var parts: [String] = []
        if let health = power.health { parts.append("\(health)%") }
        if let cycles = power.cycleCount { parts.append("\(cycles) cycles") }
        if let temperature = power.temperature { parts.append(String(format: "%.0f °C", temperature)) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
