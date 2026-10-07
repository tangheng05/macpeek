import MacpeekCore
import SwiftUI

struct NetworkSection: View {
    let model: AppModel
    /// A fixed number of rows keeps the popover from resizing as apps come and go.
    static let rows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Network", systemImage: "arrow.up.arrow.down")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↓ \(Format.rate(model.network.download))  ↑ \(Format.rate(model.network.upload))")
                    .monospacedDigit()
            }
            ForEach(0..<Self.rows, id: \.self) { index in
                if index < model.talkers.count {
                    row(model.talkers[index])
                } else if index == 0 {
                    Text("No app is using the network right now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    row(AppTraffic(name: "", download: 0, upload: 0)).hidden()
                }
            }
        }
    }

    private func row(_ app: AppTraffic) -> some View {
        HStack {
            Text(app.name).lineLimit(1)
            Spacer()
            Text("↓ \(Format.rate(Double(app.download)))  ↑ \(Format.rate(Double(app.upload)))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
