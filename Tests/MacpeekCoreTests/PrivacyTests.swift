import Foundation
import Testing
@testable import MacpeekCore

@Suite struct PrivacyTests {
    let home = NetworkState(primaryIPv4: "en0", primaryIPv6: "en0",
                            ipv4: ["en0": ["192.168.1.20"], "utun0": [], "utun1": []],
                            ipv6: ["en0": ["2001:db8::5"], "utun0": ["fe80::1"]],
                            dnsServers: ["192.168.1.1"])

    @Test func noVPNWithIdleTunnels() {
        #expect(VPNDetector.evaluate(home) == .off)
    }

    @Test func fullTunnelVPN() {
        var network = home
        network.primaryIPv4 = "utun4"
        network.ipv4["utun4"] = ["10.8.0.2"]
        network.serviceNames["utun4"] = "Work VPN"
        #expect(VPNDetector.evaluate(network) == VPNState(connected: true, interface: "utun4", fullTunnel: true, name: "Work VPN"))
    }

    @Test func wireGuardStyleTunnel() {
        var network = home
        network.ipv4["utun5"] = ["10.2.0.2"]
        let vpn = VPNDetector.evaluate(network)
        #expect(vpn.connected)
        #expect(vpn.interface == "utun5")
        #expect(!vpn.fullTunnel)
    }

    @Test func linkLocalTunnelIsNotAVPN() {
        var network = home
        network.ipv4["utun6"] = ["169.254.3.3"]
        #expect(!VPNDetector.evaluate(network).connected)
    }

    @Test func dnsThroughTunnel() {
        var network = home
        network.ipv4["utun5"] = ["10.2.0.2"]
        let vpn = VPNDetector.evaluate(network)
        network.dnsServers = ["10.2.0.1"]
        #expect(LeakChecks.dns(network, vpn: vpn) == .protected)
        network.dnsServers = ["1.1.1.1"]
        network.tunnelDNSServers = ["1.1.1.1"]
        #expect(LeakChecks.dns(network, vpn: vpn) == .protected)
        network.dnsServers = ["127.0.0.1"]
        #expect(LeakChecks.dns(network, vpn: vpn) == .protected)
    }

    @Test func dnsLeakingToRouter() {
        var network = home
        network.ipv4["utun5"] = ["10.2.0.2"]
        let vpn = VPNDetector.evaluate(network)
        #expect(LeakChecks.dns(network, vpn: vpn) == .exposed)
        #expect(LeakChecks.dns(network, vpn: .off) == .unknown)
    }

    @Test func ipv6Checks() {
        var network = home
        network.ipv4["utun5"] = ["10.2.0.2"]
        let vpn = VPNDetector.evaluate(network)
        #expect(LeakChecks.ipv6(publicIPv6: nil, network: network, vpn: vpn) == .protected)
        #expect(LeakChecks.ipv6(publicIPv6: "2001:db8::5", network: network, vpn: vpn) == .exposed)
        network.ipv6["utun5"] = ["fd00::2"]
        #expect(LeakChecks.ipv6(publicIPv6: "2001:db8::9", network: network, vpn: vpn) == .protected)
        #expect(LeakChecks.ipv6(publicIPv6: "2001:db8::5", network: network, vpn: .off) == .unknown)
    }

    @Test func parsesIPInfo() throws {
        let json = #"{"ip":"219.100.37.236","city":"Tokyo","region":"Tokyo","country":"JP","org":"AS2516 KDDI CORPORATION"}"#
        let info = try #require(PublicIPLookup.parseIPInfo(Data(json.utf8)))
        #expect(info == IPInfo(ip: "219.100.37.236", city: "Tokyo", region: "Tokyo", countryCode: "JP", isp: "KDDI CORPORATION"))
        #expect(PublicIPLookup.parseIPInfo(Data("{}".utf8)) == nil)
    }

    @Test func parsesFreeIPAPI() throws {
        let json = #"{"ipAddress":"1.2.3.4","cityName":"Phnom Penh","regionName":"Phnom Penh","countryCode":"KH","asnOrganization":"Ezecom"}"#
        let info = try #require(PublicIPLookup.parseFreeIPAPI(Data(json.utf8)))
        #expect(info.countryCode == "KH")
        #expect(info.isp == "Ezecom")
    }

    @Test func parsesCloudflareTrace() throws {
        let trace = "fl=961f22\nh=1.1.1.1\nip=152.42.217.118\ncolo=SIN\nloc=SG\nwarp=off\n"
        let info = try #require(PublicIPLookup.parseCloudflareTrace(Data(trace.utf8)))
        #expect(info == IPInfo(ip: "152.42.217.118", countryCode: "SG"))
        // Cloudflare uses XX and T1 (Tor) when it can't place an address.
        #expect(PublicIPLookup.parseCloudflareTrace(Data("ip=1.2.3.4\nloc=XX\n".utf8)) == IPInfo(ip: "1.2.3.4"))
        #expect(PublicIPLookup.parseCloudflareTrace(Data("<html>blocked</html>".utf8)) == nil)
    }

    @Test func verdicts() {
        let vpn = VPNState(connected: true, interface: "utun5")
        let ip = IPInfo(ip: "1.2.3.4")
        #expect(PrivacyReport(vpn: vpn, ip: ip, dns: .protected, ipv6: .protected, checkedAt: .now).verdict == .protected)
        #expect(PrivacyReport(vpn: vpn, ip: ip, dns: .exposed, ipv6: .protected, checkedAt: .now).verdict == .leaking)
        #expect(PrivacyReport(vpn: .off, ip: ip, dns: .unknown, ipv6: .unknown, checkedAt: .now).verdict == .unprotected)
    }

    @Test func reportText() {
        let report = PrivacyReport(vpn: VPNState(connected: true, interface: "utun5", name: "Proton"),
                                   ip: IPInfo(ip: "1.2.3.4", city: "Tokyo", countryCode: "JP", isp: "KDDI"),
                                   dns: .protected, ipv6: .exposed, checkedAt: .now)
        #expect(report.text.contains("VPN: Proton"))
        #expect(report.text.contains("Location: Tokyo, JP"))
        #expect(report.text.contains("IPv6: Exposed"))
    }
}
