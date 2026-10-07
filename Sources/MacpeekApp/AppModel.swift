import AppKit
import MacpeekCore
import Observation

@MainActor
@Observable
final class AppModel {
    // System
    private(set) var cpu = CPUUsage.zero
    private(set) var cpuHistory = History<Double>(capacity: MenuBarGraph.historyLength)
    private(set) var memory: MemoryUsage?
    private(set) var network = NetworkRate.zero
    private(set) var disk: DiskUsage?
    private(set) var power: PowerInfo?
    private(set) var thermal = Thermal.current()
    private(set) var apps: [ProcessUsage] = []
    private(set) var talkers: [AppTraffic] = []

    // Privacy
    private(set) var vpn = VPNState.off
    private(set) var report: PrivacyReport?
    private(set) var checking = false

    var popoverOpen = false {
        didSet { if popoverOpen != oldValue { popoverChanged() } }
    }

    // Settings
    var interval: Double {
        didSet { save(interval, "interval"); if timer != nil { scheduleSampling() } }
    }
    var showNetwork: Bool { didSet { save(showNetwork, "showNetwork") } }
    var showDisk: Bool { didSet { save(showDisk, "showDisk") } }
    var showVPN: Bool { didSet { save(showVPN, "showVPN") } }
    var alertVPN: Bool { didSet { save(alertVPN, "alertVPN") } }
    var alertIPChange: Bool { didSet { save(alertIPChange, "alertIPChange") } }
    var alertMemory: Bool { didSet { save(alertMemory, "alertMemory") } }
    var alertThermal: Bool { didSet { save(alertThermal, "alertThermal") } }

    let updater = Updater()
    @ObservationIgnored let notifier = Notifier()
    @ObservationIgnored var openSettings: (() -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var recheckTimer: Timer?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var lastCounters: (counters: NetworkCounters, time: Date)?
    @ObservationIgnored private let processSampler = ProcessSampler()
    @ObservationIgnored private var talkersTask: Task<Void, Never>?
    @ObservationIgnored private var networkSettle: Task<Void, Never>?
    @ObservationIgnored private var networkWatcher: NetworkWatcher?
    @ObservationIgnored private var powerWatcher: PowerWatcher?
    @ObservationIgnored private var pressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var lastMemoryAlert = Date.distantPast

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "interval": 2.0, "showNetwork": false, "showDisk": false, "showVPN": true,
            "alertVPN": true, "alertIPChange": true, "alertMemory": true, "alertThermal": false,
        ])
        interval = defaults.double(forKey: "interval")
        showNetwork = defaults.bool(forKey: "showNetwork")
        showDisk = defaults.bool(forKey: "showDisk")
        showVPN = defaults.bool(forKey: "showVPN")
        alertVPN = defaults.bool(forKey: "alertVPN")
        alertIPChange = defaults.bool(forKey: "alertIPChange")
        alertMemory = defaults.bool(forKey: "alertMemory")
        alertThermal = defaults.bool(forKey: "alertThermal")
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func start() {
        notifier.requestPermission()
        disk = DiskInfo.read()
        power = BatteryInfo.read()
        vpn = VPNDetector.evaluate(VPNDetector.read())
        tick()
        scheduleSampling()
        networkWatcher = NetworkWatcher { [weak self] in self?.networkChanged() }
        powerWatcher = PowerWatcher { [weak self] in self?.power = BatteryInfo.read() }
        watchMemoryPressure()
        watchThermal()
        watchSleep()
        Task { await runFullTest() }
        updater.start()
    }

    // MARK: Sampling

    /// One timer for everything cheap. The tolerance lets macOS fold its wake-ups into others.
    private func scheduleSampling() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date.now
        if let ticks = CPUSampler.read() {
            if let lastTicks {
                cpu = CPUSampler.usage(from: lastTicks, to: ticks)
                cpuHistory.append(cpu.total)
            }
            lastTicks = ticks
        }
        if let reading = MemorySampler.read(), reading != memory { memory = reading }
        if let counters = NetworkSampler.read() {
            if let last = lastCounters {
                network = NetworkSampler.rate(from: last.counters, to: counters, seconds: now.timeIntervalSince(last.time))
            }
            lastCounters = (counters, now)
        }
        tickCount += 1
        // Disk space barely moves and is the slowest read, so about once a minute.
        if tickCount % max(1, Int(60 / interval)) == 0 { disk = DiskInfo.read() }
        if popoverOpen { apps = processSampler.sample() }
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
        talkersTask?.cancel()
    }

    private func resume() {
        guard timer == nil else { return }
        lastTicks = nil
        lastCounters = nil
        scheduleSampling()
        networkChanged()
    }

    private func popoverChanged() {
        talkersTask?.cancel()
        guard popoverOpen else { return }
        processSampler.reset()
        apps = processSampler.sample()
        disk = DiskInfo.read()
        power = BatteryInfo.read()
        talkersTask = Task { [weak self] in
            while !Task.isCancelled {
                let traffic = await NetworkSampler.topTalkers()
                guard !Task.isCancelled, let self, self.popoverOpen else { return }
                self.talkers = traffic
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Privacy

    private func networkChanged() {
        let wasConnected = vpn.connected
        let previousName = vpn.name
        vpn = VPNDetector.evaluate(VPNDetector.read())
        // Networks flap for a few seconds while switching, so judge once they settle.
        networkSettle?.cancel()
        networkSettle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            await self.runFullTest()
            if wasConnected, !self.vpn.connected, self.alertVPN {
                self.notifier.post(title: "VPN disconnected",
                                   body: "Your traffic no longer goes through \(previousName ?? "the VPN").")
            }
        }
    }

    func runFullTest() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let network = VPNDetector.read()
        vpn = VPNDetector.evaluate(network)
        async let ipLookup = PublicIPLookup.fetch()
        async let ipv6Lookup = PublicIPLookup.fetchIPv6()
        let (ip, ipv6) = await (ipLookup, ipv6Lookup)
        let previous = report
        report = PrivacyReport(vpn: vpn, ip: ip,
                               dns: LeakChecks.dns(network, vpn: vpn),
                               ipv6: LeakChecks.ipv6(publicIPv6: ipv6, network: network, vpn: vpn),
                               checkedAt: .now)
        if alertIPChange, vpn.connected, previous?.vpn.connected == true,
           let before = previous?.ip?.ip, let after = ip?.ip, before != after {
            notifier.post(title: "Public IP changed", body: "Now \(after), was \(before).")
        }
        scheduleRecheck()
    }

    /// While a VPN is up, look again every 30 minutes in case it silently stopped routing.
    private func scheduleRecheck() {
        recheckTimer?.invalidate()
        recheckTimer = nil
        guard vpn.connected else { return }
        let timer = Timer(timeInterval: 1800, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.runFullTest() }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        recheckTimer = timer
    }

    func copyReport() {
        if let report { copy(report.text) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Events

    private func watchMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.memoryPressureChanged() }
        }
        source.resume()
        pressureSource = source
    }

    private func memoryPressureChanged() {
        let pressure = MemorySampler.pressure()
        if var reading = memory {
            reading.pressure = pressure
            memory = reading
        }
        guard pressure == .critical, alertMemory, Date.now.timeIntervalSince(lastMemoryAlert) > 1800 else { return }
        lastMemoryAlert = .now
        let top = apps.max { $0.memory < $1.memory }
        notifier.post(title: "Memory is running out",
                      body: top.map { "\($0.name) is using \(Format.memory($0.memory))." } ?? "Quit an app you aren't using.")
    }

    private func watchThermal() {
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.thermalChanged() }
        }
    }

    private func thermalChanged() {
        let level = Thermal.current()
        let wasThrottling = thermal.isThrottling
        thermal = level
        if level.isThrottling, !wasThrottling, alertThermal {
            notifier.post(title: "Your Mac is running hot", body: "macOS is slowing it down to cool off.")
        }
    }

    private func watchSleep() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            }
        }
    }
}
