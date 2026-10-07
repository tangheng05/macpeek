import Foundation

public enum Thermal {
    public static func current() -> ThermalLevel {
        level(ProcessInfo.processInfo.thermalState)
    }

    public static func level(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}
