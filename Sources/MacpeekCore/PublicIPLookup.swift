import Foundation

/// Public IP, place and ISP. Called on network changes and when asked, never on a loop.
public enum PublicIPLookup {
    static let primary = URL(string: "https://ipinfo.io/json")!
    static let fallback = URL(string: "https://freeipapi.com/api/json")!
    static let ipv6Only = URL(string: "https://api6.ipify.org")!
    /// Reached by IP, so it still works when a VPN's DNS blocks lookup services. Country only.
    static let lastResort = URL(string: "https://1.1.1.1/cdn-cgi/trace")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    public static func fetch() async -> IPInfo? {
        if let data = await get(primary), let info = parseIPInfo(data) { return info }
        if let data = await get(fallback), let info = parseFreeIPAPI(data) { return info }
        if let data = await get(lastResort), let info = parseCloudflareTrace(data) { return info }
        return nil
    }

    /// Nil when there's no IPv6 route to the internet.
    public static func fetchIPv6() async -> String? {
        guard let data = await get(ipv6Only) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.contains(":") ? text : nil
    }

    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    static func parseIPInfo(_ data: Data) -> IPInfo? {
        struct Raw: Decodable {
            let ip: String
            let city: String?
            let region: String?
            let country: String?
            let org: String?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        return IPInfo(ip: raw.ip, city: raw.city, region: raw.region, countryCode: raw.country,
                      isp: raw.org.map(stripASN))
    }

    static func parseFreeIPAPI(_ data: Data) -> IPInfo? {
        struct Raw: Decodable {
            let ipAddress: String
            let cityName: String?
            let regionName: String?
            let countryCode: String?
            let asnOrganization: String?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        return IPInfo(ip: raw.ipAddress, city: raw.cityName, region: raw.regionName,
                      countryCode: raw.countryCode, isp: raw.asnOrganization)
    }

    /// `key=value` lines; `loc` is a country code, or XX/T1 when Cloudflare can't place it.
    static func parseCloudflareTrace(_ data: Data) -> IPInfo? {
        var fields: [Substring: Substring] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            fields[line[..<equals]] = line[line.index(after: equals)...]
        }
        guard let ip = fields["ip"], !ip.isEmpty else { return nil }
        let country = fields["loc"].flatMap { $0 == "XX" || $0 == "T1" ? nil : String($0) }
        return IPInfo(ip: String(ip), countryCode: country)
    }

    /// "AS2516 KDDI CORPORATION" -> "KDDI CORPORATION".
    static func stripASN(_ org: String) -> String {
        guard org.hasPrefix("AS"), let space = org.firstIndex(of: " ") else { return org }
        return String(org[org.index(after: space)...])
    }
}
