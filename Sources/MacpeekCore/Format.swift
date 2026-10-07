import Foundation

public enum Format {
    /// Disk sizes, in Finder's 1000-based units: "366.4 GB".
    public static func bytes(_ value: UInt64) -> String {
        scaled(Double(value), base: 1000, units: ["B", "KB", "MB", "GB", "TB"])
    }

    /// Memory, in Activity Monitor's 1024-based units: "12.3 GB".
    public static func memory(_ value: UInt64) -> String {
        scaled(Double(value), base: 1024, units: ["B", "KB", "MB", "GB", "TB"])
    }

    /// "1.2 MB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        scaled(max(0, bytesPerSecond), base: 1000, units: ["B/s", "KB/s", "MB/s", "GB/s"])
    }

    /// 0...1 to "42%".
    public static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, fraction) * 100).rounded()))%"
    }

    public static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        return "\(Int(seconds / 86_400)) d ago"
    }

    /// 125 -> "2:05".
    public static func duration(minutes: Int) -> String {
        "\(minutes / 60):" + (minutes % 60 < 10 ? "0" : "") + "\(minutes % 60)"
    }

    /// "JP" -> "🇯🇵".
    public static func flag(_ countryCode: String) -> String? {
        let code = countryCode.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return nil }
        let scalars = code.unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// "JP" -> "Japan".
    public static func countryName(_ countryCode: String) -> String {
        Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
    }

    private static func scaled(_ value: Double, base: Double, units: [String]) -> String {
        var amount = value
        var unit = 0
        while amount >= base, unit < units.count - 1 {
            amount /= base
            unit += 1
        }
        if unit == 0 { return "\(Int(amount)) \(units[0])" }
        return String(format: "%.1f", amount) + " " + units[unit]
    }
}
