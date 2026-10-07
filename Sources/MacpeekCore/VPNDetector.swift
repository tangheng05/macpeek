import Foundation
import SystemConfiguration

/// What the network looks like right now, read from the System Configuration dynamic store.
public struct NetworkState: Equatable, Sendable {
    public var primaryIPv4: String?
    public var primaryIPv6: String?
    /// Interface name to its addresses.
    public var ipv4: [String: [String]]
    public var ipv6: [String: [String]]
    public var dnsServers: [String]
    /// DNS servers handed out by services that run over a tunnel.
    public var tunnelDNSServers: [String]
    /// Interface name to the name the user sees in System Settings.
    public var serviceNames: [String: String]

    public init(primaryIPv4: String? = nil, primaryIPv6: String? = nil, ipv4: [String: [String]] = [:],
                ipv6: [String: [String]] = [:], dnsServers: [String] = [], tunnelDNSServers: [String] = [],
                serviceNames: [String: String] = [:]) {
        self.primaryIPv4 = primaryIPv4
        self.primaryIPv6 = primaryIPv6
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.dnsServers = dnsServers
        self.tunnelDNSServers = tunnelDNSServers
        self.serviceNames = serviceNames
    }
}

public enum VPNDetector {
    /// Key patterns to watch; any change to these can mean a VPN came up or went down.
    public static let watchedPatterns = [
        "State:/Network/Global/IPv4",
        "State:/Network/Global/IPv6",
        "State:/Network/Global/DNS",
        "State:/Network/Interface/[^/]+/IPv4",
    ]

    private static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]

    public static func isTunnel(_ interface: String) -> Bool {
        tunnelPrefixes.contains { interface.hasPrefix($0) }
    }

    /// A tunnel only counts once it has a real IPv4 address: macOS keeps several idle `utun`s
    /// around (iCloud Private Relay, Back to My Mac) that only carry link-local IPv6.
    public static func evaluate(_ network: NetworkState) -> VPNState {
        if let primary = network.primaryIPv4, isTunnel(primary) {
            return VPNState(connected: true, interface: primary, fullTunnel: true, name: network.serviceNames[primary])
        }
        let live = network.ipv4
            .filter { isTunnel($0.key) && $0.value.contains(where: isRoutable) }
            .keys.sorted()
        guard let interface = live.first else { return .off }
        // WireGuard-style clients route 0/1 and 128/1 through the tunnel without becoming primary.
        return VPNState(connected: true, interface: interface, fullTunnel: false, name: network.serviceNames[interface])
    }

    static func isRoutable(_ address: String) -> Bool {
        !address.isEmpty && !address.hasPrefix("169.254.") && !address.hasPrefix("127.")
    }

    /// Pass nil to use a temporary session.
    public static func read(_ store: SCDynamicStore? = nil) -> NetworkState {
        func value(_ key: String) -> [String: Any]? {
            SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
        }
        func keys(_ pattern: String) -> [String] {
            SCDynamicStoreCopyKeyList(store, pattern as CFString) as? [String] ?? []
        }
        /// `State:/Network/Interface/en0/IPv4` -> `en0`.
        func component(_ key: String) -> String? {
            let parts = key.split(separator: "/")
            return parts.count > 3 ? String(parts[3]) : nil
        }

        var state = NetworkState()
        state.primaryIPv4 = value("State:/Network/Global/IPv4")?["PrimaryInterface"] as? String
        state.primaryIPv6 = value("State:/Network/Global/IPv6")?["PrimaryInterface"] as? String
        state.dnsServers = value("State:/Network/Global/DNS")?["ServerAddresses"] as? [String] ?? []
        for key in keys("State:/Network/Interface/[^/]+/IPv4") {
            if let name = component(key) { state.ipv4[name] = value(key)?["Addresses"] as? [String] ?? [] }
        }
        for key in keys("State:/Network/Interface/[^/]+/IPv6") {
            if let name = component(key) { state.ipv6[name] = value(key)?["Addresses"] as? [String] ?? [] }
        }
        for key in keys("State:/Network/Service/[^/]+/IPv4") {
            guard let id = component(key), let interface = value(key)?["InterfaceName"] as? String,
                  isTunnel(interface) else { continue }
            if let name = value("Setup:/Network/Service/\(id)")?["UserDefinedName"] as? String {
                state.serviceNames[interface] = name
            }
            state.tunnelDNSServers += value("State:/Network/Service/\(id)/DNS")?["ServerAddresses"] as? [String] ?? []
        }
        return state
    }
}
