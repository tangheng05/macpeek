import Foundation

public struct ResolverInfo: Equatable, Sendable {
    public var ip: String
    public var country: String?
    public var org: String?

    public init(ip: String, country: String? = nil, org: String? = nil) {
        self.ip = ip
        self.country = country
        self.org = org
    }
}

/// Asks a service which resolver actually reached it. Only runs when the user asks for it.
public enum DNSLeakTest {
    static let publicResolvers = ["cloudflare", "google", "quad9", "opendns", "adguard"]

    public static func read() async -> ResolverInfo? {
        // A fresh name each time so no cache sits between the resolver and the service.
        let name = UUID().uuidString.lowercased().prefix(12)
        guard let url = URL(string: "http://\(name).edns.ip-api.com/json") else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        guard let (data, response) = try? await URLSession(configuration: config).data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    /// `geo` looks like "Tokyo, Japan - SoftEther".
    static func parse(_ data: Data) -> ResolverInfo? {
        struct Raw: Decodable {
            struct DNS: Decodable { let ip: String; let geo: String? }
            let dns: DNS
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        let parts = raw.dns.geo?.components(separatedBy: " - ")
        let place = parts?.first?.components(separatedBy: ", ").last
        let org = parts?.count == 2 ? parts?.last : nil
        return ResolverInfo(ip: raw.dns.ip, country: place, org: org)
    }

    /// Exposed when the local check already says so, or when a private resolver sits in another
    /// country than the VPN exit. Public resolvers are fine anywhere.
    public static func evaluate(resolver: ResolverInfo?, exit: IPInfo?, local: CheckResult) -> CheckResult {
        guard let resolver else { return local }
        if local == .exposed { return .exposed }
        let org = resolver.org?.lowercased() ?? ""
        if publicResolvers.contains(where: org.contains) { return .protected }
        guard let country = resolver.country, let code = exit?.countryCode,
              let exitCountry = Locale(identifier: "en_US").localizedString(forRegionCode: code) else { return local }
        return country.caseInsensitiveCompare(exitCountry) == .orderedSame ? .protected : .exposed
    }
}
