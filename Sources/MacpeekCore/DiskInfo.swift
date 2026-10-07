import Foundation

public enum DiskInfo {
    /// Free space as Finder counts it, including space macOS can purge on demand.
    /// This call can take a moment, so refresh it rarely.
    public static func read(path: String = "/") -> DiskUsage? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return DiskUsage(free: UInt64(max(0, free)), total: UInt64(max(0, total)))
    }
}
