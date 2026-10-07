import Darwin
import Foundation

public struct NetworkCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public enum NetworkSampler {
    /// Total bytes through physical interfaces. Uses the 64-bit counters from NET_RT_IFLIST2,
    /// since getifaddrs' 32-bit ones wrap every 4 GB.
    public static func read() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        var counters = NetworkCounters(received: 0, sent: 0)
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if countsTowardTotal(interfaceName(info.ifm_index)) {
                        counters.received &+= info.ifm_data.ifi_ibytes
                        counters.sent &+= info.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return counters
    }

    /// Wi-Fi, Ethernet and cellular only. VPN traffic also crosses one of these, so counting
    /// tunnels too would double it.
    public static func countsTowardTotal(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    public static func rate(from old: NetworkCounters, to new: NetworkCounters, seconds: Double) -> NetworkRate {
        guard seconds > 0 else { return .zero }
        // Counters drop when an interface goes away; treat that sample as idle.
        let down = new.received >= old.received ? Double(new.received - old.received) : 0
        let up = new.sent >= old.sent ? Double(new.sent - old.sent) : 0
        return NetworkRate(download: down / seconds, upload: up / seconds)
    }

    static func interfaceName(_ index: UInt16) -> String {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &name) != nil else { return "" }
        return String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: Per-app traffic

    /// Bytes each app moved over about one second, from nettop. Spawns a process, so only call
    /// it while the popover is open.
    public static func topTalkers(limit: Int = 5) async -> [AppTraffic] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
                process.arguments = ["-P", "-d", "-L", "2", "-s", "1", "-x", "-J", "bytes_in,bytes_out"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let traffic = parseNettop(String(decoding: data, as: UTF8.self))
                continuation.resume(returning: Array(traffic.prefix(limit)))
            }
        }
    }

    /// Reads the last sample of `nettop -P -x -J bytes_in,bytes_out` CSV, busiest first.
    /// Rows look like `Google Chrome H.1234,5120,880,`.
    public static func parseNettop(_ output: String) -> [AppTraffic] {
        let lines = output.split(whereSeparator: \.isNewline)
        guard let header = lines.lastIndex(where: { $0.contains("bytes_in") }) else { return [] }
        var apps: [String: AppTraffic] = [:]
        for line in lines[lines.index(after: header)...] {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, let down = UInt64(fields[1]), let up = UInt64(fields[2]) else { continue }
            var name = String(fields[0])
            if let dot = name.lastIndex(of: "."), Int(name[name.index(after: dot)...]) != nil {
                name = String(name[..<dot])
            }
            guard !name.isEmpty else { continue }
            var app = apps[name] ?? AppTraffic(name: name, download: 0, upload: 0)
            app.download += down
            app.upload += up
            apps[name] = app
        }
        return apps.values.filter { $0.total > 0 }.sorted { $0.total > $1.total }
    }
}
