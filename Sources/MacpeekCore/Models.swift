import Foundation

public struct CPUUsage: Equatable, Sendable {
    /// Fractions of all cores, 0...1.
    public var user: Double
    public var system: Double
    public var total: Double { min(1, user + system) }

    public init(user: Double, system: Double) {
        self.user = user
        self.system = system
    }

    public static let zero = CPUUsage(user: 0, system: 0)
}

public enum MemoryPressure: String, Sendable, Codable {
    case normal, warning, critical
}

public struct MemoryUsage: Equatable, Sendable {
    public var used: UInt64
    public var total: UInt64
    public var pressure: MemoryPressure
    /// How close macOS is to running out, 0...1. Unlike `used`, this stays low while spare RAM
    /// is only holding caches.
    public var pressureFraction: Double
    public var fraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }

    public init(used: UInt64, total: UInt64, pressure: MemoryPressure, pressureFraction: Double = 0) {
        self.used = used
        self.total = total
        self.pressure = pressure
        self.pressureFraction = pressureFraction
    }
}

/// One app, with its helper processes folded in.
public struct ProcessUsage: Identifiable, Equatable, Sendable {
    /// The .app path when there is one, else the executable name.
    public var id: String
    public var name: String
    public var pid: Int32
    public var bundlePath: String?
    /// Percent of one core, like Activity Monitor (can pass 100).
    public var cpu: Double
    public var memory: UInt64
    /// Watts, from the kernel's per-process energy counter. Always 0 on Intel.
    public var power: Double

    public init(id: String, name: String, pid: Int32, bundlePath: String?, cpu: Double, memory: UInt64,
                power: Double = 0) {
        self.id = id
        self.name = name
        self.pid = pid
        self.bundlePath = bundlePath
        self.cpu = cpu
        self.memory = memory
        self.power = power
    }
}

public struct NetworkRate: Equatable, Sendable {
    public var download: Double
    public var upload: Double

    public init(download: Double, upload: Double) {
        self.download = download
        self.upload = upload
    }

    public static let zero = NetworkRate(download: 0, upload: 0)
}

public struct AppTraffic: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var download: UInt64
    public var upload: UInt64
    public var total: UInt64 { download + upload }

    public init(name: String, download: UInt64, upload: UInt64) {
        self.name = name
        self.download = download
        self.upload = upload
    }
}

public struct DiskUsage: Equatable, Sendable {
    public var free: UInt64
    public var total: UInt64
    public var used: UInt64 { total > free ? total - free : 0 }

    public init(free: UInt64, total: UInt64) {
        self.free = free
        self.total = total
    }
}

public struct PowerInfo: Equatable, Sendable {
    public var percent: Int
    public var charging: Bool
    public var pluggedIn: Bool
    /// Minutes to empty, or to full while charging. Nil while macOS is still estimating.
    public var minutesLeft: Int?
    public var cycleCount: Int?
    public var health: Int?
    /// Power flowing out of (or into) the battery right now.
    public var watts: Double?
    /// Celsius.
    public var temperature: Double?

    public init(percent: Int, charging: Bool, pluggedIn: Bool, minutesLeft: Int?, cycleCount: Int?, health: Int?,
                watts: Double? = nil, temperature: Double? = nil) {
        self.percent = percent
        self.charging = charging
        self.pluggedIn = pluggedIn
        self.minutesLeft = minutesLeft
        self.cycleCount = cycleCount
        self.health = health
        self.watts = watts
        self.temperature = temperature
    }
}

public enum ThermalLevel: String, Sendable, Codable {
    case nominal, fair, serious, critical

    public var isThrottling: Bool { self == .serious || self == .critical }
}

public struct VPNState: Equatable, Sendable {
    public var connected: Bool
    public var interface: String?
    /// False for split tunnels, where only some traffic goes through the VPN.
    public var fullTunnel: Bool
    public var name: String?

    public init(connected: Bool, interface: String? = nil, fullTunnel: Bool = false, name: String? = nil) {
        self.connected = connected
        self.interface = interface
        self.fullTunnel = fullTunnel
        self.name = name
    }

    public static let off = VPNState(connected: false)
}

public struct IPInfo: Equatable, Sendable, Codable {
    public var ip: String
    public var city: String?
    public var region: String?
    /// ISO 3166 alpha-2, like "JP".
    public var countryCode: String?
    public var isp: String?

    public init(ip: String, city: String? = nil, region: String? = nil, countryCode: String? = nil, isp: String? = nil) {
        self.ip = ip
        self.city = city
        self.region = region
        self.countryCode = countryCode
        self.isp = isp
    }
}

public enum CheckResult: String, Equatable, Sendable {
    case protected, exposed, unknown
}

public struct PrivacyReport: Equatable, Sendable {
    public var vpn: VPNState
    public var ip: IPInfo?
    public var dns: CheckResult
    public var ipv6: CheckResult
    public var checkedAt: Date

    public init(vpn: VPNState, ip: IPInfo?, dns: CheckResult, ipv6: CheckResult, checkedAt: Date) {
        self.vpn = vpn
        self.ip = ip
        self.dns = dns
        self.ipv6 = ipv6
        self.checkedAt = checkedAt
    }

    public var verdict: Verdict {
        guard vpn.connected else { return .unprotected }
        return dns == .exposed || ipv6 == .exposed ? .leaking : .protected
    }

    public enum Verdict: Sendable {
        case protected, leaking, unprotected

        public var title: String {
            switch self {
            case .protected: "Protected"
            case .leaking: "Leaking"
            case .unprotected: "Not Protected"
            }
        }
    }

    /// Plain text for Copy Report.
    public var text: String {
        var lines = [verdict.title]
        if let ip { lines.append("IP: \(ip.ip)") }
        lines.append("VPN: \(vpn.connected ? (vpn.name ?? vpn.interface ?? "Connected") : "Off")")
        if let ip {
            let place = [ip.city, ip.countryCode].compactMap { $0 }.joined(separator: ", ")
            if !place.isEmpty { lines.append("Location: \(place)") }
            if let isp = ip.isp { lines.append("ISP: \(isp)") }
        }
        lines.append("DNS: \(dns.rawValue.capitalized)")
        lines.append("IPv6: \(ipv6.rawValue.capitalized)")
        lines.append("Checked: \(checkedAt.formatted(date: .abbreviated, time: .standard))")
        return lines.joined(separator: "\n")
    }
}
