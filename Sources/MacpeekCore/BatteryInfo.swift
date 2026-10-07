import Foundation
import IOKit
import IOKit.ps

public enum BatteryInfo {
    /// Nil on Macs without a battery.
    public static func read() -> PowerInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() else { return nil }
        for source in (list as NSArray) as [AnyObject] {
            guard let values = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  values["Type"] as? String == "InternalBattery" else { continue }
            return parse(values, registry: registryValues())
        }
        return nil
    }

    static func parse(_ values: [String: Any], registry: [String: Int]) -> PowerInfo? {
        guard let current = values["Current Capacity"] as? Int,
              let max = values["Max Capacity"] as? Int, max > 0 else { return nil }
        let charging = values["Is Charging"] as? Bool ?? false
        let minutes = (charging ? values["Time to Full Charge"] : values["Time to Empty"]) as? Int
        let rawMax = registry["AppleRawMaxCapacity"] ?? registry["MaxCapacity"]
        return PowerInfo(percent: current * 100 / max,
                         charging: charging,
                         pluggedIn: values["Power Source State"] as? String == "AC Power",
                         minutesLeft: minutes.flatMap { $0 > 0 ? $0 : nil },
                         cycleCount: registry["CycleCount"],
                         health: health(rawMax: rawMax, design: registry["DesignCapacity"]),
                         watts: watts(millivolts: registry["Voltage"], milliamps: registry["Amperage"]),
                         temperature: registry["Temperature"].map { Double($0) / 100 })
    }

    /// Full-charge capacity as a percentage of what the battery held new.
    static func health(rawMax: Int?, design: Int?) -> Int? {
        guard let rawMax, let design, design > 0, rawMax > 100 else { return nil }
        return min(100, Int((Double(rawMax) * 100 / Double(design)).rounded()))
    }

    /// Amperage is negative while discharging; the sign is shown by the charging state instead.
    static func watts(millivolts: Int?, milliamps: Int?) -> Double? {
        guard let millivolts, let milliamps else { return nil }
        return abs(Double(millivolts) * Double(milliamps)) / 1_000_000
    }

    private static func registryValues() -> [String: Int] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var result: [String: Int] = [:]
        let keys = ["CycleCount", "AppleRawMaxCapacity", "MaxCapacity", "DesignCapacity", "Voltage", "Amperage", "Temperature"]
        for key in keys {
            let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
            // NSNumber, so a negative amperage stored as a huge unsigned value reads back signed.
            if let number = value as? NSNumber { result[key] = number.intValue }
        }
        return result
    }
}
