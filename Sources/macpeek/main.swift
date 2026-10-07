import Foundation
import MacpeekCore

/// `macpeek status [--json]`: a one-shot reading for scripts.
struct Status: Encodable {
    let cpu: Double
    let memoryUsed: UInt64?
    let memoryTotal: UInt64?
    let memoryPressure: String?
    let diskFree: UInt64?
    let diskTotal: UInt64?
    let vpnConnected: Bool
    let vpnInterface: String?
    let vpnName: String?
}

func readStatus() -> Status {
    var cpu = 0.0
    if let first = CPUSampler.read() {
        usleep(500_000)
        if let second = CPUSampler.read() { cpu = CPUSampler.usage(from: first, to: second).total }
    }
    let memory = MemorySampler.read()
    let disk = DiskInfo.read()
    let vpn = VPNDetector.evaluate(VPNDetector.read())
    return Status(cpu: (cpu * 1000).rounded() / 1000, memoryUsed: memory?.used, memoryTotal: memory?.total,
                  memoryPressure: memory?.pressure.rawValue, diskFree: disk?.free, diskTotal: disk?.total,
                  vpnConnected: vpn.connected, vpnInterface: vpn.interface, vpnName: vpn.name)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first(where: { !$0.hasPrefix("-") }) ?? "status" {
case "status":
    let status = readStatus()
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(status), as: UTF8.self))
    } else {
        print("CPU     \(Format.percent(status.cpu))")
        if let used = status.memoryUsed, let total = status.memoryTotal {
            print("Memory  \(Format.memory(used)) of \(Format.memory(total)) (\(status.memoryPressure ?? "normal"))")
        }
        if let free = status.diskFree { print("Disk    \(Format.bytes(free)) free") }
        print("VPN     \(status.vpnConnected ? (status.vpnName ?? status.vpnInterface ?? "on") : "off")")
    }
default:
    FileHandle.standardError.write(Data("usage: macpeek status [--json]\n".utf8))
    exit(1)
}
