import Darwin
import Foundation

/// One process before it's folded into its app.
public struct RawProcess: Equatable, Sendable {
    public var pid: Int32
    public var path: String
    public var cpu: Double
    public var memory: UInt64

    public init(pid: Int32, path: String, cpu: Double, memory: UInt64) {
        self.pid = pid
        self.path = path
        self.cpu = cpu
        self.memory = memory
    }
}

/// Per-app CPU and memory. Only run this while someone is looking: it touches every process.
/// Processes owned by other users (root daemons) can't be read without a helper, so they're skipped.
public final class ProcessSampler {
    private var previous: [Int32: UInt64] = [:]
    private var previousTime: UInt64 = 0

    /// rusage CPU times are in Mach ticks, which aren't nanoseconds on Apple silicon.
    private static let nanosPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return timebase.denom == 0 ? 1 : Double(timebase.numer) / Double(timebase.denom)
    }()

    public init() {}

    /// The first call only primes the counters, so every app reads 0% CPU.
    public func sample() -> [ProcessUsage] {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let elapsed = previousTime == 0 ? 0 : Double(now - previousTime)
        var current: [Int32: UInt64] = [:]
        var rows: [RawProcess] = []
        for pid in Self.allPIDs() where pid > 0 {
            guard let usage = Self.rusage(pid) else { continue }
            let cpuTime = UInt64(Double(usage.ri_user_time &+ usage.ri_system_time) * Self.nanosPerTick)
            current[pid] = cpuTime
            var cpu = 0.0
            if elapsed > 0, let old = previous[pid], cpuTime >= old {
                cpu = Double(cpuTime - old) / elapsed * 100
            }
            rows.append(RawProcess(pid: pid, path: Self.path(pid), cpu: cpu, memory: usage.ri_phys_footprint))
        }
        previous = current
        previousTime = now
        return Self.group(rows)
    }

    /// Call when the popover closes, so the next open doesn't average over the time it was shut.
    public func reset() {
        previous = [:]
        previousTime = 0
    }

    /// Folds helpers into their app: Chrome's renderers count as Chrome.
    public static func group(_ rows: [RawProcess]) -> [ProcessUsage] {
        var apps: [String: ProcessUsage] = [:]
        for row in rows {
            let bundle = appBundle(in: row.path)
            let key = bundle ?? (row.path.isEmpty ? "pid \(row.pid)" : row.path)
            let isMain = bundle.map { row.path.hasPrefix($0 + "/Contents/MacOS/") } ?? true
            if var app = apps[key] {
                app.cpu += row.cpu
                app.memory += row.memory
                if isMain { app.pid = row.pid }
                apps[key] = app
            } else {
                apps[key] = ProcessUsage(id: key, name: displayName(path: bundle ?? key), pid: row.pid,
                                         bundlePath: bundle, cpu: row.cpu, memory: row.memory)
            }
        }
        return Array(apps.values)
    }

    /// The outermost .app the executable lives in, if any.
    public static func appBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func displayName(path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }

    static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return found > 0 ? Array(pids.prefix(Int(found))) : []
    }

    static func rusage(_ pid: Int32) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info : nil
    }

    static func path(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
