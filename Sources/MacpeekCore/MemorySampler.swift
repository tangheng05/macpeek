import Darwin
import Foundation

/// The page counts Activity Monitor's "Memory Used" is built from.
public struct MemoryPages: Equatable, Sendable {
    public var `internal`: UInt64
    public var purgeable: UInt64
    public var wired: UInt64
    public var compressed: UInt64

    public init(internal: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64) {
        self.internal = `internal`
        self.purgeable = purgeable
        self.wired = wired
        self.compressed = compressed
    }

    /// App memory + wired + compressed, the same sum Activity Monitor shows.
    public func usedBytes(pageSize: UInt64) -> UInt64 {
        let app = `internal` > purgeable ? `internal` - purgeable : 0
        return (app + wired + compressed) * pageSize
    }
}

public enum MemorySampler {
    private static let host = mach_host_self()
    private static let pageSize: UInt64 = {
        var size: vm_size_t = 0
        return host_page_size(mach_host_self(), &size) == KERN_SUCCESS ? UInt64(size) : 16_384
    }()

    public static func read() -> MemoryUsage? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = MemoryPages(internal: UInt64(stats.internal_page_count),
                                purgeable: UInt64(stats.purgeable_count),
                                wired: UInt64(stats.wire_count),
                                compressed: UInt64(stats.compressor_page_count))
        return MemoryUsage(used: pages.usedBytes(pageSize: pageSize),
                           total: ProcessInfo.processInfo.physicalMemory,
                           pressure: pressure(),
                           pressureFraction: pressureFraction())
    }

    /// The same figure as `memory_pressure`'s "System-wide memory free percentage", inverted.
    public static func pressureFraction() -> Double {
        var free: Int32 = 100
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &free, &size, nil, 0) == 0 else { return 0 }
        return pressureFraction(freePercent: free)
    }

    static func pressureFraction(freePercent: Int32) -> Double {
        Double(100 - min(100, max(0, freePercent))) / 100
    }

    /// The kernel's own pressure level, the one behind Activity Monitor's graph colour.
    public static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return pressure(level: level)
    }

    static func pressure(level: Int32) -> MemoryPressure {
        switch level {
        case 4: .critical
        case 2: .warning
        default: .normal
        }
    }
}
