import Foundation
import Testing
@testable import MacpeekCore

@Suite struct SamplerTests {
    @Test func cpuUsageFromTicks() {
        let old = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let new = CPUTicks(user: 300, system: 100, idle: 1600, nice: 0)
        let usage = CPUSampler.usage(from: old, to: new)
        #expect(abs(usage.user - 0.2) < 0.0001)
        #expect(abs(usage.system - 0.05) < 0.0001)
        #expect(abs(usage.total - 0.25) < 0.0001)
    }

    @Test func cpuTicksWrapAround() {
        let old = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let new = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)
        #expect(abs(CPUSampler.usage(from: old, to: new).user - 0.5) < 0.0001)
    }

    @Test func cpuNoTimePassed() {
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        #expect(CPUSampler.usage(from: ticks, to: ticks) == .zero)
    }

    @Test func liveCountersRead() {
        #expect(CPUSampler.read() != nil)
        #expect((MemorySampler.read()?.used ?? 0) > 0)
        #expect(NetworkSampler.read() != nil)
    }

    @Test func memoryUsedMatchesActivityMonitor() {
        let pages = MemoryPages(internal: 1000, purgeable: 200, wired: 300, compressed: 100)
        #expect(pages.usedBytes(pageSize: 16_384) == 1200 * 16_384)
        #expect(MemoryPages(internal: 10, purgeable: 50, wired: 0, compressed: 0).usedBytes(pageSize: 1) == 0)
    }

    @Test func pressureLevels() {
        #expect(MemorySampler.pressure(level: 1) == .normal)
        #expect(MemorySampler.pressure(level: 2) == .warning)
        #expect(MemorySampler.pressure(level: 4) == .critical)
    }

    /// kern.memorystatus_level is the free percentage that `memory_pressure` prints.
    @Test func pressureFromFreePercent() {
        #expect(MemorySampler.pressureFraction(freePercent: 79) == 0.21)
        #expect(MemorySampler.pressureFraction(freePercent: 100) == 0)
        #expect(MemorySampler.pressureFraction(freePercent: 0) == 1)
        #expect(MemorySampler.pressureFraction(freePercent: -5) == 1)
        #expect(MemorySampler.pressureFraction(freePercent: 120) == 0)
    }

    @Test func liveMemoryPressure() throws {
        let memory = try #require(MemorySampler.read())
        #expect((0...1).contains(memory.pressureFraction))
        #expect(memory.pressureFraction < 1)
    }

    @Test func networkRate() {
        let old = NetworkCounters(received: 1000, sent: 500)
        let new = NetworkCounters(received: 5000, sent: 700)
        #expect(NetworkSampler.rate(from: old, to: new, seconds: 2) == NetworkRate(download: 2000, upload: 100))
        #expect(NetworkSampler.rate(from: new, to: old, seconds: 2) == .zero)
        #expect(NetworkSampler.rate(from: old, to: new, seconds: 0) == .zero)
    }

    @Test func onlyPhysicalInterfacesCount() {
        #expect(NetworkSampler.countsTowardTotal("en0"))
        #expect(NetworkSampler.countsTowardTotal("pdp_ip0"))
        #expect(!NetworkSampler.countsTowardTotal("utun3"))
        #expect(!NetworkSampler.countsTowardTotal("lo0"))
        #expect(!NetworkSampler.countsTowardTotal("awdl0"))
    }

    @Test func parsesNettopSnapshot() {
        let output = """
        ,bytes_in,bytes_out,
        Google Chrome H.1234,5000,800,
        Slack.900,300,100,
        garbage line
        """
        let snapshot = NetworkSampler.parseSnapshot(output)
        #expect(snapshot.count == 2)
        #expect(snapshot["Google Chrome H.1234"] == NetworkCounters(received: 5000, sent: 800))
        #expect(NetworkSampler.parseSnapshot("").isEmpty)
    }

    @Test func talkersFromSnapshots() {
        let old = ["Chrome H.1": NetworkCounters(received: 1000, sent: 100),
                   "Chrome H.2": NetworkCounters(received: 0, sent: 0),
                   "Slack.3": NetworkCounters(received: 500, sent: 500),
                   "Gone.4": NetworkCounters(received: 9, sent: 9)]
        let new = ["Chrome H.1": NetworkCounters(received: 5000, sent: 500),
                   "Chrome H.2": NetworkCounters(received: 2000, sent: 300),
                   "Slack.3": NetworkCounters(received: 500, sent: 500),
                   "New.5": NetworkCounters(received: 99_999, sent: 0)]
        let talkers = NetworkSampler.talkers(from: old, to: new, seconds: 2, limit: 3)
        // Helpers fold by name, idle apps drop out, and a process with no earlier reading is skipped.
        #expect(talkers == [AppTraffic(name: "Chrome H", download: 3000, upload: 350)])
        let reset = ["Chrome H.1": NetworkCounters(received: 10, sent: 10)]
        #expect(NetworkSampler.talkers(from: old, to: reset, seconds: 2, limit: 3).isEmpty)
        #expect(NetworkSampler.talkers(from: old, to: new, seconds: 0, limit: 3).isEmpty)
    }

    @Test func groupsHelpersUnderApp() {
        let chrome = "/Applications/Google Chrome.app"
        let rows = [
            RawProcess(pid: 20, path: chrome + "/Contents/Frameworks/x/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper",
                       cpu: 10, memory: 100),
            RawProcess(pid: 10, path: chrome + "/Contents/MacOS/Google Chrome", cpu: 5, memory: 50),
            RawProcess(pid: 30, path: "/usr/sbin/cfprefsd", cpu: 1, memory: 5),
        ]
        let apps = ProcessSampler.group(rows).sorted { $0.cpu > $1.cpu }
        #expect(apps.count == 2)
        #expect(apps[0] == ProcessUsage(id: chrome, name: "Google Chrome", pid: 10, bundlePath: chrome, cpu: 15, memory: 150))
        #expect(apps[1].name == "cfprefsd")
        #expect(apps[1].bundlePath == nil)
    }

    @Test func appBundlePath() {
        #expect(ProcessSampler.appBundle(in: "/Applications/Slack.app/Contents/MacOS/Slack") == "/Applications/Slack.app")
        #expect(ProcessSampler.appBundle(in: "/usr/bin/top") == nil)
    }

    @Test func liveProcessSample() {
        let sampler = ProcessSampler()
        _ = sampler.sample()
        #expect(!sampler.sample().isEmpty)
    }

    /// `yes` spins one core flat out, so it should read close to 100%, like Activity Monitor.
    @Test func busyProcessReadsAboutOneCore() async throws {
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        busy.standardOutput = FileHandle.nullDevice
        try busy.run()
        defer { busy.terminate() }
        let sampler = ProcessSampler()
        _ = sampler.sample()
        try await Task.sleep(for: .seconds(2))
        let usage = try #require(sampler.sample().first { $0.pid == busy.processIdentifier })
        print("yes: \(usage.cpu)% CPU, \(usage.power) W")
        #expect(usage.cpu > 60)
        #expect(usage.cpu < 130)
        #expect(usage.memory > 0)
    }

    @Test func groupingSumsPower() {
        let rows = [
            RawProcess(pid: 1, path: "/Applications/Slack.app/Contents/MacOS/Slack", cpu: 1, memory: 1, power: 0.5),
            RawProcess(pid: 2, path: "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper",
                       cpu: 1, memory: 1, power: 0.25),
        ]
        #expect(ProcessSampler.group(rows).first?.power == 0.75)
    }

    @Test func batteryParsing() throws {
        let values: [String: Any] = [
            "Current Capacity": 80, "Max Capacity": 100, "Is Charging": false,
            "Power Source State": "Battery Power", "Time to Empty": 125,
        ]
        let registry = ["CycleCount": 312, "AppleRawMaxCapacity": 4500, "DesignCapacity": 5000,
                        "Voltage": 12_000, "Amperage": -1_000, "Temperature": 3050]
        let info = try #require(BatteryInfo.parse(values, registry: registry))
        #expect(info.percent == 80)
        #expect(!info.pluggedIn)
        #expect(info.minutesLeft == 125)
        #expect(info.cycleCount == 312)
        #expect(info.health == 90)
        #expect(info.watts == 12)
        #expect(info.temperature == 30.5)
    }

    /// Apple silicon on macOS 26+: MaxCapacity is a percentage and the real capacities sit in BatteryData.
    @Test func batteryHealthFromNominalCapacity() throws {
        let values: [String: Any] = ["Current Capacity": 80, "Max Capacity": 100]
        let registry = ["MaxCapacity": 100, "NominalChargeCapacity": 6258, "DesignCapacity": 6249]
        #expect(try #require(BatteryInfo.parse(values, registry: registry)).health == 100)
        let worn = ["MaxCapacity": 100, "NominalChargeCapacity": 5300, "DesignCapacity": 6249]
        #expect(try #require(BatteryInfo.parse(values, registry: worn)).health == 85)
    }

    @Test func liveBatteryHasHealth() {
        guard let info = BatteryInfo.read() else { return }
        #expect(info.health != nil)
    }

    @Test func batteryStillEstimating() throws {
        let values: [String: Any] = ["Current Capacity": 50, "Max Capacity": 100, "Is Charging": true,
                                     "Power Source State": "AC Power", "Time to Full Charge": -1]
        let info = try #require(BatteryInfo.parse(values, registry: [:]))
        #expect(info.minutesLeft == nil)
        #expect(info.pluggedIn)
        #expect(info.health == nil)
        #expect(info.watts == nil)
    }
}
