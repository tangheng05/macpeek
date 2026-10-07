import AppKit
import MacpeekCore
import Observation
import ServiceManagement

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
    var coloredMenuBar: Bool { didSet { save(coloredMenuBar, "coloredMenuBar") } }
    var alertVPN: Bool { didSet { save(alertVPN, "alertVPN") } }
    var alertIPChange: Bool { didSet { save(alertIPChange, "alertIPChange") } }
    var alertMemory: Bool { didSet { save(alertMemory, "alertMemory") } }
    var alertThermal: Bool { didSet { save(alertThermal, "alertThermal") } }
    /// Nil means the shortcut is turned off.
    var shortcut: KeyCombo? {
        didSet {
            let stored = shortcut.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
            save(stored ?? "off", "keyCombo")
        }
    }
    var shortcutTaken = false
    var recordingShortcut = false
    private(set) var openAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var notificationsAllowed = false

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
            "interval": 2.0, "showNetwork": false, "showDisk": false, "showVPN": true, "coloredMenuBar": false,
            "alertVPN": true, "alertIPChange": true, "alertMemory": true, "alertThermal": false,
        ])
        interval = defaults.double(forKey: "interval")
        showNetwork = defaults.bool(forKey: "showNetwork")
        showDisk = defaults.bool(forKey: "showDisk")
        showVPN = defaults.bool(forKey: "showVPN")
        coloredMenuBar = defaults.bool(forKey: "coloredMenuBar")
        alertVPN = defaults.bool(forKey: "alertVPN")
        alertIPChange = defaults.bool(forKey: "alertIPChange")
        alertMemory = defaults.bool(forKey: "alertMemory")
        alertThermal = defaults.bool(forKey: "alertThermal")
        let combo = defaults.string(forKey: "keyCombo")
        shortcut = combo == "off" ? nil : combo.flatMap { try? JSONDecoder().decode(KeyCombo.self, from: Data($0.utf8)) } ?? .default
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func start() {
        Task { await refreshNotificationStatus() }
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
                let traffic = await NetworkSampler.topTalkers(limit: NetworkSection.rows)
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

    // MARK: Preferences

    /// Only works for the copy in Applications; a build run from Terminal can't register.
    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshNotificationStatus() async {
        notificationsAllowed = await notifier.isAllowed()
    }

    /// Asks once; after a "Don't Allow" only System Settings can change it, so open that instead.
    func allowNotifications() async {
        if await notifier.wasDenied() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            return
        }
        notificationsAllowed = await notifier.requestPermission()
    }

    func copyReport() {
        if let report { copy(report.text) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    #if DEBUG
    /// Fixed data for snapshot renders.
    func loadSample() {
        cpu = CPUUsage(user: 0.18, system: 0.07)
        for index in 0..<MenuBarGraph.historyLength {
            cpuHistory.append(0.12 + 0.1 * sin(Double(index) / 3) + (index > 20 ? 0.2 : 0))
        }
        memory = MemoryUsage(used: 11_800_000_000, total: 17_179_869_184, pressure: .normal)
        network = NetworkRate(download: 1_240_000, upload: 86_000)
        disk = DiskUsage(free: 366_400_000_000, total: 494_380_000_000)
        power = PowerInfo(percent: 82, charging: false, pluggedIn: false, minutesLeft: 312, cycleCount: 214,
                          health: 91, watts: 7.4, temperature: 31.2)
        apps = [
            ProcessUsage(id: "safari", name: "Safari", pid: 1, bundlePath: "/Applications/Safari.app", cpu: 14.2, memory: 2_100_000_000, power: 1.84),
            ProcessUsage(id: "mail", name: "Mail", pid: 2, bundlePath: "/System/Applications/Mail.app", cpu: 3.1, memory: 410_000_000, power: 0.21),
            ProcessUsage(id: "music", name: "Music", pid: 3, bundlePath: "/System/Applications/Music.app", cpu: 6.8, memory: 380_000_000, power: 0.62),
            ProcessUsage(id: "finder", name: "Finder", pid: 4, bundlePath: "/System/Library/CoreServices/Finder.app", cpu: 0.4, memory: 160_000_000, power: 0.03),
            ProcessUsage(id: "notes", name: "Notes", pid: 5, bundlePath: "/System/Applications/Notes.app", cpu: 1.2, memory: 240_000_000, power: 0.09),
        ]
        talkers = [
            AppTraffic(name: "Safari", download: 1_100_000, upload: 40_000),
            AppTraffic(name: "Music", download: 120_000, upload: 6_000),
        ]
        vpn = VPNState(connected: true, interface: "utun4", fullTunnel: true, name: "WireGuard")
        report = PrivacyReport(vpn: vpn,
                               ip: IPInfo(ip: "219.100.37.236", city: "Tokyo", region: "Tokyo", countryCode: "JP", isp: "SoftEther"),
                               dns: .protected, ipv6: .protected, checkedAt: .now)
    }
    #endif

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
