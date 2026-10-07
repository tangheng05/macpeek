import MacpeekCore
import SwiftUI

struct PrivacySection: View {
    let model: AppModel

    var body: some View {
        let report = model.report
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: shieldIcon(report))
                    .font(.system(size: 30))
                    .foregroundStyle(shieldColor(report))
                VStack(alignment: .leading, spacing: 2) {
                    Text(report?.verdict.title ?? "Checking…")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(report?.ip?.ip ?? (report == nil ? " " : "Offline"))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let ip = report?.ip?.ip {
                            Button { model.copy(ip) } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless)
                                .help("Copy IP address")
                        }
                    }
                }
            }
            InfoRow(icon: "network", label: "VPN Status", value: vpnText)
            InfoRow(icon: "globe", label: "IP Location", value: location(report?.ip))
            InfoRow(icon: "building.2", label: "ISP", value: report?.ip?.isp ?? "—")
            InfoRow(icon: "server.rack", label: "DNS Route", value: text(report?.dns), valueColor: color(report?.dns))
            InfoRow(icon: "6.circle", label: "IPv6 Leak", value: text(report?.ipv6), valueColor: color(report?.ipv6))
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(model.checking ? "Checking…" : report.map { "Last checked: \(Format.ago($0.checkedAt, now: context.date))" } ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Button("Run Full Test") { Task { await model.runFullTest() } }
                    .keyboardShortcut("r")
                    .disabled(model.checking)
                Button("Copy Report") { model.copyReport() }
                    .keyboardShortcut("c")
                    .disabled(report == nil)
            }
        }
    }

    private var vpnText: String {
        guard model.vpn.connected else { return "Off" }
        return model.vpn.name ?? "Connected"
    }

    private func location(_ ip: IPInfo?) -> String {
        guard let code = ip?.countryCode else { return "—" }
        return [Format.flag(code), Format.countryName(code)].compactMap { $0 }.joined(separator: " ")
    }

    private func text(_ result: CheckResult?) -> String {
        switch result {
        case .protected: "Protected"
        case .exposed: "Exposed"
        case .unknown, nil: "—"
        }
    }

    private func color(_ result: CheckResult?) -> Color {
        result == .exposed ? .orange : .primary
    }

    private func shieldIcon(_ report: PrivacyReport?) -> String {
        switch report?.verdict {
        case .protected: "checkmark.shield.fill"
        case .leaking: "exclamationmark.shield.fill"
        case .unprotected, nil: "shield.slash"
        }
    }

    private func shieldColor(_ report: PrivacyReport?) -> Color {
        switch report?.verdict {
        case .protected: .purple
        case .leaking: .orange
        case .unprotected, nil: .secondary
        }
    }
}
