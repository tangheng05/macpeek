import MacpeekCore
import SwiftUI

struct NetworkSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Network", systemImage: "arrow.up.arrow.down")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↓ \(Format.rate(model.network.download))  ↑ \(Format.rate(model.network.upload))")
                    .monospacedDigit()
            }
            if model.talkers.isEmpty {
                Text("No app is using the network right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.talkers) { app in
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
    }
}
