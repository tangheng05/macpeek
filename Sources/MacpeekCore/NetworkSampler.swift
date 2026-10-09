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
        eachInterface(buffer, length: length) { _, name, data in
            if countsTowardTotal(name) {
                counters.received &+= data.ifi_ibytes
                counters.sent &+= data.ifi_obytes
            }
        }
        return counters
    }

    /// Each RTM_IFINFO2 message is followed by a sockaddr_dl holding the interface name, which saves
    /// an if_indextoname call per interface.
    static func eachInterface(_ buffer: [UInt8], length: Int, _ body: (UInt16, String, if_data64) -> Void) {
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let end = offset + Int(header.ifm_msglen)
                guard header.ifm_msglen > 0, end <= length else { break }
                let address = offset + MemoryLayout<if_msghdr2>.size
                // sockaddr_dl: sdl_nlen at byte 5, the name from byte 8.
                if Int32(header.ifm_type) == RTM_IFINFO2, address + 8 <= end {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let nameEnd = min(end, address + 8 + Int(raw[address + 5]))
                    body(info.ifm_index, String(decoding: raw[(address + 8)..<nameEnd], as: UTF8.self), info.ifm_data)
                }
                offset = end
            }
        }
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

    // MARK: Per-app traffic

    /// Bytes each process has moved so far, keyed by nettop's `name.pid`. A single nettop sample
    /// is nearly free; its delta mode (`-d -L 2`) burns over a second of CPU per call.
    public static func snapshot() async -> [String: NetworkCounters] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
                // -n skips hostname lookups, which can stall a sample for seconds when DNS is slow.
                process.arguments = ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: [:])
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: parseSnapshot(String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// Rows look like `Google Chrome H.1234,5120,880,`.
    public static func parseSnapshot(_ output: String) -> [String: NetworkCounters] {
        var result: [String: NetworkCounters] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, !fields[0].isEmpty, let down = UInt64(fields[1]), let up = UInt64(fields[2]) else { continue }
            result[String(fields[0])] = NetworkCounters(received: down, sent: up)
        }
        return result
    }

    /// Per-second traffic between two snapshots, helpers folded by name, busiest first.
    public static func talkers(from old: [String: NetworkCounters], to new: [String: NetworkCounters],
                               seconds: Double, limit: Int) -> [AppTraffic] {
        guard seconds > 0 else { return [] }
        var apps: [String: (down: UInt64, up: UInt64)] = [:]
        for (key, counters) in new {
            guard let before = old[key], counters.received >= before.received, counters.sent >= before.sent else { continue }
            var name = key
            if let dot = key.lastIndex(of: "."), Int(key[key.index(after: dot)...]) != nil { name = String(key[..<dot]) }
            let total = apps[name] ?? (0, 0)
            apps[name] = (total.down + counters.received - before.received, total.up + counters.sent - before.sent)
        }
        return apps
            .map { AppTraffic(name: $0.key, download: UInt64(Double($0.value.down) / seconds), upload: UInt64(Double($0.value.up) / seconds)) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { $0 }
    }
}
