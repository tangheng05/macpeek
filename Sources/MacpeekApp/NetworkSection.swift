import MacpeekCore
import SwiftUI

struct NetworkSection: View {
    let model: AppModel
    /// A fixed number of rows keeps the popover from resizing as apps come and go.
    static let rows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Network") {
                Text("↓ \(Format.rate(model.network.download))   ↑ \(Format.rate(model.network.upload))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            let scale = max(100_000, model.downloadHistory.values.max() ?? 0, model.uploadHistory.values.max() ?? 0)
            ZStack {
                Sparkline(values: model.downloadHistory.values.map { $0 / scale }, capacity: model.downloadHistory.capacity)
                    .fill(Color.accentColor.gradient)
                Sparkline(values: model.uploadHistory.values.map { $0 / scale }, capacity: model.uploadHistory.capacity)
                    .fill(Color.secondary.opacity(0.5))
            }
            .frame(height: 24)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 3))
            let apps = byApp
            ForEach(0..<Self.rows, id: \.self) { index in
                if let apps, index < apps.count {
                    AppRow(icon: AppIcons.icon(for: apps[index].path), name: apps[index].name,
                           value: "↓ \(Format.rate(apps[index].down))   ↑ \(Format.rate(apps[index].up))")
                } else if index == 0 {
                    Text(apps == nil ? "Measuring…" : "No app is using the network right now.")
                        .foregroundStyle(.secondary)
                        .frame(height: AppRow.height)
                } else {
                    Color.clear.frame(height: AppRow.height)
                }
            }
        }
    }

    /// Helper processes folded into the app they belong to, busiest first.
    private var byApp: [(name: String, path: String?, down: Double, up: Double)]? {
        guard let talkers = model.talkers else { return nil }
        var apps: [String: (path: String?, down: Double, up: Double)] = [:]
        for traffic in talkers {
            let app = AppIcons.app(forProcess: traffic.name)
            let total = apps[app.name] ?? (app.path, 0, 0)
            apps[app.name] = (total.path, total.down + Double(traffic.download), total.up + Double(traffic.upload))
        }
        return apps
            .map { (name: $0.key, path: $0.value.path, down: $0.value.down, up: $0.value.up) }
            .sorted { $0.down + $0.up > $1.down + $1.up }
            .prefix(Self.rows)
            .map { $0 }
    }
}
