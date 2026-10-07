import Foundation

/// Local checks only: they read the routing and resolver setup, they don't send test queries.
public enum LeakChecks {
    /// Protected when every active resolver came from the VPN, sits in the tunnel's own /24,
    /// or is a local forwarder.
    public static func dns(_ network: NetworkState, vpn: VPNState) -> CheckResult {
        guard vpn.connected, !network.dnsServers.isEmpty else { return .unknown }
        let fromTunnel = Set(network.tunnelDNSServers)
        let tunnelAddresses = vpn.interface.flatMap { network.ipv4[$0] } ?? []
        let safe = network.dnsServers.allSatisfy { server in
            fromTunnel.contains(server) || server.hasPrefix("127.") || server == "::1"
                || tunnelAddresses.contains { sameSlash24(server, $0) }
        }
        return safe ? .protected : .exposed
    }

    /// `publicIPv6` is what an IPv6-only lookup returned, nil if it failed.
    /// Exposed when IPv6 reaches the internet but doesn't go through the tunnel.
    public static func ipv6(publicIPv6: String?, network: NetworkState, vpn: VPNState) -> CheckResult {
        guard vpn.connected else { return .unknown }
        guard publicIPv6 != nil else { return .protected }
        if let primary = network.primaryIPv6, VPNDetector.isTunnel(primary) { return .protected }
        let tunnelHasIPv6 = vpn.interface.flatMap { network.ipv6[$0] }?.contains { !$0.lowercased().hasPrefix("fe80") } ?? false
        return tunnelHasIPv6 ? .protected : .exposed
    }

    static func sameSlash24(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: "."), y = b.split(separator: ".")
        return x.count == 4 && y.count == 4 && x.prefix(3) == y.prefix(3)
    }
}
