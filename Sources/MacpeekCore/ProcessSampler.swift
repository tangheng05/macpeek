import Darwin
import Foundation

/// One process before it's folded into its app.
public struct RawProcess: Equatable, Sendable {
    public var pid: Int32
    public var path: String
    public var cpu: Double
    public var memory: UInt64
    public var power: Double

    public init(pid: Int32, path: String, cpu: Double, memory: UInt64, power: Double = 0) {
        self.pid = pid
        self.path = path
        self.cpu = cpu
        self.memory = memory
        self.power = power
    }
}

/// Per-app CPU, memory and power. Only run this while someone is looking: it touches every process.
/// Processes owned by other users (root daemons) can't be read without a helper, so they're skipped.
public final class ProcessSampler {
    private var previous: [Int32: (cpu: UInt64, energy: UInt64)] = [:]
    private var previousTime: UInt64 = 0
    /// Keyed by start time too, since pids get reused.
    private var paths: [Int32: (start: UInt64, path: String)] = [:]

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
        var current: [Int32: (cpu: UInt64, energy: UInt64)] = [:]
        var rows: [RawProcess] = []
        var seenPaths: [Int32: (start: UInt64, path: String)] = [:]
        for pid in Self.ownPIDs() where pid > 0 {
            guard let usage = Self.rusage(pid) else { continue }
            let start = usage.ri_proc_start_abstime
            let path = paths[pid].flatMap { $0.start == start ? $0.path : nil } ?? Self.path(pid)
            seenPaths[pid] = (start, path)
            let cpuTime = UInt64(Double(usage.ri_user_time &+ usage.ri_system_time) * Self.nanosPerTick)
            current[pid] = (cpuTime, usage.ri_energy_nj)
            var cpu = 0.0
            var power = 0.0
            if elapsed > 0, let old = previous[pid] {
                if cpuTime >= old.cpu { cpu = Double(cpuTime - old.cpu) / elapsed * 100 }
                // Nanojoules per nanosecond is watts. Intel Macs report no energy, so this stays 0.
                if usage.ri_energy_nj >= old.energy { power = Double(usage.ri_energy_nj - old.energy) / elapsed }
            }
            rows.append(RawProcess(pid: pid, path: path, cpu: cpu, memory: usage.ri_phys_footprint,
                                   power: power))
        }
        previous = current
        previousTime = now
        paths = seenPaths
        return Self.group(rows)
    }

    /// Call when the popover closes, so the next open doesn't average over the time it was shut.
    public func reset() {
        previous = [:]
        paths = [:]
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
                app.power += row.power
                if isMain { app.pid = row.pid }
                apps[key] = app
            } else {
                apps[key] = ProcessUsage(id: key, name: displayName(path: bundle ?? key), pid: row.pid,
                                         bundlePath: bundle, cpu: row.cpu, memory: row.memory, power: row.power)
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
        let last = path.lastIndex(of: "/").map { path[path.index(after: $0)...] } ?? path[...]
        return String(last.hasSuffix(".app") ? last.dropLast(4) : last)
    }

    /// Only this user's processes: rusage fails for anyone else's, so listing them is wasted work.
    static func ownPIDs() -> [Int32] {
        let uid = UInt32(getuid())
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard bytes > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
        let found = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_UID_ONLY), uid, $0.baseAddress, Int32($0.count)) }
        return found > 0 ? Array(pids.prefix(Int(found) / MemoryLayout<Int32>.size)) : []
    }

    static func rusage(_ pid: Int32) -> rusage_info_v6? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
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
