import MacpeekCore
import SwiftUI

struct PrivacySection: View {
    let model: AppModel
    @AppStorage("showPrivacyDetails") private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            status
            disclosure
            if expanded { details }
        }
    }

    // MARK: Status

    private var status: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: .rect(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(model.report?.verdict.title ?? "Checking…")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { Task { await model.runFullTest(userInitiated: true) } } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: model.checking)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .disabled(model.checking)
            .help("Run Full Test (⌘R)")
        }
        .padding(10)
        .background(tint.opacity(0.13), in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var openWiFi: Bool {
        model.report?.verdict == .unprotected && model.onOpenWiFi
    }

    private var icon: String {
        if openWiFi { return "wifi.exclamationmark" }
        return switch model.report?.verdict {
        case .protected: "checkmark.shield.fill"
        case .leaking: "exclamationmark.shield.fill"
        case .unprotected, nil: "shield.slash.fill"
        }
    }

    private var tint: Color {
        if openWiFi { return .orange }
        return switch model.report?.verdict {
        case .protected: .green
        case .leaking: .orange
        case .unprotected, nil: Color(nsColor: .systemGray)
        }
    }

    private var subtitle: String {
        guard let report = model.report else { return "Looking up your connection" }
        if openWiFi { return "Open Wi-Fi, traffic isn't encrypted" }
        switch report.verdict {
        case .leaking:
            return report.dns == .exposed ? "DNS requests go around the VPN" : "IPv6 traffic goes around the VPN"
        case .protected, .unprotected:
            let vpn = report.vpn.connected ? (report.vpn.name ?? "VPN on") : "VPN off"
            return [vpn, place(report.ip)].compactMap { $0 }.joined(separator: ", ")
        }
    }

    // MARK: Details

    private var disclosure: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack {
                Text("Details")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Spacer()
                if !expanded, let ip = model.report?.ip?.ip {
                    Text(ip)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
    }

    private var details: some View {
        let report = model.report
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Public IP")
                Spacer(minLength: 12)
                Text(report?.ip?.ip ?? (report == nil ? "—" : "Lookup failed"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let ip = report?.ip?.ip {
                    Button { model.copy(ip) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy IP address")
                }
            }
            ValueRow(label: "Location", value: fullPlace(report?.ip) ?? "—")
            ValueRow(label: "Provider", value: report?.ip?.isp ?? "—")
            if let wifi = model.wifi {
                ValueRow(label: "Wi-Fi", value: wifi.security.isInsecure ? "\(wifi.security.title), not encrypted" : wifi.security.title,
                         valueColor: model.onOpenWiFi ? .orange : .secondary)
            }
            if let dns = report?.dns, dns != .unknown {
                ValueRow(label: "DNS", value: dns == .protected ? "Through the VPN" : "Around the VPN",
                         valueColor: dns == .exposed ? .orange : .secondary)
            }
            if let resolver = report?.resolver {
                ValueRow(label: "Resolver", value: [resolver.ip, resolver.country].compactMap { $0 }.joined(separator: ", "))
            }
            if let ipv6 = report?.ipv6, ipv6 != .unknown {
                ValueRow(label: "IPv6", value: ipv6 == .protected ? "Through the VPN" : "Around the VPN",
                         valueColor: ipv6 == .exposed ? .orange : .secondary)
            }
            HStack {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(report.map { "Checked \(Format.ago($0.checkedAt, now: context.date))" } ?? "")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Report") { model.copyReport() }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("c")
                    .disabled(report == nil)
            }
        }
        .padding(.horizontal, 2)
    }

    private func place(_ ip: IPInfo?) -> String? {
        guard let code = ip?.countryCode else { return nil }
        return [Format.flag(code), Format.countryName(code)].compactMap { $0 }.joined(separator: " ")
    }

    private func fullPlace(_ ip: IPInfo?) -> String? {
        guard let country = place(ip) else { return nil }
        guard let city = ip?.city, !city.isEmpty else { return country }
        return "\(city), \(country)"
    }
}
