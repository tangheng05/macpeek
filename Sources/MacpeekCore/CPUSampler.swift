import Darwin

/// Cumulative CPU ticks across all cores. They are 32-bit and wrap, so diffs use wrapping math.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUSampler {
    private static let host = mach_host_self()

    public static func read() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: t.0, system: t.1, idle: t.2, nice: t.3)
    }

    public static func usage(from old: CPUTicks, to new: CPUTicks) -> CPUUsage {
        let user = Double((new.user &- old.user) &+ (new.nice &- old.nice))
        let system = Double(new.system &- old.system)
        let idle = Double(new.idle &- old.idle)
        let all = user + system + idle
        guard all > 0 else { return .zero }
        return CPUUsage(user: user / all, system: system / all)
    }
}
