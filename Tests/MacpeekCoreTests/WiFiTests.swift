import CoreWLAN
import Testing
@testable import MacpeekCore

@Suite struct WiFiTests {
    let open = WiFiState(interface: "en0", security: .open, rssi: -60, channel: 6, band: "2.4 GHz", txRate: 144)

    @Test func securityMapping() {
        #expect(WiFiInfo.security(.none) == .open)
        #expect(WiFiInfo.security(.WEP) == .wep)
        #expect(WiFiInfo.security(.dynamicWEP) == .wep)
        #expect(WiFiInfo.security(.wpaPersonal) == .wpa)
        #expect(WiFiInfo.security(.wpaPersonalMixed) == .wpa2)
        #expect(WiFiInfo.security(.wpa3Transition) == .wpa3)
        #expect(WiFiInfo.security(.OWE) == .enhancedOpen)
        #expect(WiFiInfo.security(.wpa2Enterprise) == .enterprise)
        #expect(WiFiInfo.security(.unknown) == .unknown)
    }

    @Test func insecureTypes() {
        #expect(WiFiSecurity.open.isInsecure)
        #expect(WiFiSecurity.wep.isInsecure)
        #expect(!WiFiSecurity.enhancedOpen.isInsecure)
        #expect(!WiFiSecurity.wpa2.isInsecure)
        #expect(!WiFiSecurity.unknown.isInsecure)
    }

    @Test func bands() {
        #expect(WiFiInfo.band(.band2GHz) == "2.4 GHz")
        #expect(WiFiInfo.band(.band6GHz) == "6 GHz")
        #expect(WiFiInfo.band(.bandUnknown) == nil)
    }

    @Test func signalLevels() {
        #expect(WiFiInfo.signal(rssi: -40) == .excellent)
        #expect(WiFiInfo.signal(rssi: -55) == .excellent)
        #expect(WiFiInfo.signal(rssi: -67) == .good)
        #expect(WiFiInfo.signal(rssi: -72) == .fair)
        #expect(WiFiInfo.signal(rssi: -85) == .poor)
    }

    @Test func warnsOnlyWhenTrafficUsesOpenWiFi() {
        let onWiFi = NetworkState(primaryIPv4: "en0")
        #expect(WiFiInfo.warn(open, network: onWiFi, vpn: .off))
        #expect(!WiFiInfo.warn(open, network: onWiFi, vpn: VPNState(connected: true, interface: "utun4")))
        #expect(!WiFiInfo.warn(open, network: NetworkState(primaryIPv4: "en7"), vpn: .off))
        var secured = open
        secured.security = .wpa3
        #expect(!WiFiInfo.warn(secured, network: onWiFi, vpn: .off))
        #expect(!WiFiInfo.warn(nil, network: onWiFi, vpn: .off))
    }
}
