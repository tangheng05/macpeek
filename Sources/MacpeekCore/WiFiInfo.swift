import CoreWLAN
import Foundation

public enum WiFiSecurity: String, Sendable, Codable {
    case open, wep, wpa, wpa2, wpa3, enhancedOpen, enterprise, unknown

    public var title: String {
        switch self {
        case .open: "Open"
        case .wep: "WEP"
        case .wpa: "WPA"
        case .wpa2: "WPA2"
        case .wpa3: "WPA3"
        case .enhancedOpen: "Enhanced Open"
        case .enterprise: "Enterprise"
        case .unknown: "Unknown"
        }
    }

    /// WEP is broken in minutes, so it counts as no encryption.
    public var isInsecure: Bool { self == .open || self == .wep }
}

public enum WiFiSignal: String, Sendable {
    case excellent, good, fair, poor
}

public struct WiFiState: Equatable, Sendable {
    public var interface: String
    public var security: WiFiSecurity
    /// dBm.
    public var rssi: Int
    public var channel: Int?
    public var band: String?
    /// Mb/s.
    public var txRate: Double

    public init(interface: String, security: WiFiSecurity, rssi: Int, channel: Int?, band: String?, txRate: Double) {
        self.interface = interface
        self.security = security
        self.rssi = rssi
        self.channel = channel
        self.band = band
        self.txRate = txRate
    }

    public var signal: WiFiSignal { WiFiInfo.signal(rssi: rssi) }
}

/// Security, signal, channel and rate don't need Location Services; only the network name does.
public enum WiFiInfo {
    /// Nil when Wi-Fi is off or not joined to a network.
    public static func read() -> WiFiState? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn(),
              let channel = interface.wlanChannel() else { return nil }
        return WiFiState(interface: interface.interfaceName ?? "en0", security: security(interface.security()),
                         rssi: interface.rssiValue(), channel: channel.channelNumber, band: band(channel.channelBand),
                         txRate: interface.transmitRate())
    }

    public static func security(_ security: CWSecurity) -> WiFiSecurity {
        switch security {
        case .none: .open
        case .WEP, .dynamicWEP: .wep
        case .wpaPersonal: .wpa
        case .wpaPersonalMixed, .wpa2Personal, .personal: .wpa2
        case .wpa3Personal, .wpa3Transition: .wpa3
        case .OWE, .oweTransition: .enhancedOpen
        case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise: .enterprise
        default: .unknown
        }
    }

    public static func band(_ band: CWChannelBand) -> String? {
        switch band {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: nil
        }
    }

    public static func signal(rssi: Int) -> WiFiSignal {
        switch rssi {
        case (-55)...: .excellent
        case (-67)...: .good
        case (-75)...: .fair
        default: .poor
        }
    }

    /// Only when traffic actually goes over the open network: not through a VPN, not over Ethernet.
    public static func warn(_ wifi: WiFiState?, network: NetworkState, vpn: VPNState) -> Bool {
        guard let wifi else { return false }
        return wifi.security.isInsecure && !vpn.connected && network.primaryIPv4 == wifi.interface
    }
}
