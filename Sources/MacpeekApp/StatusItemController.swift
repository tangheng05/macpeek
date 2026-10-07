import AppKit
import MacpeekCore
import SwiftUI

@MainActor
final class StatusItemController {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let hosting: NSHostingController<PopoverView>
    private var rendered: MenuBarGraph.State?
    private var outsideClickMonitor: Any?
    private var lastClosed = Date.distantPast
    private var settingsWindow: AppWindow?
    private var welcomeWindow: AppWindow?
    private let hotKey = HotKey()

    init(model: AppModel) {
        self.model = model
        hosting = NSHostingController(rootView: PopoverView(model: model, visible: false))
        hosting.sizingOptions = []
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = hosting
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastClosed = .now
                self?.stopWatchingOutsideClicks()
                self?.setPopoverContent(visible: false)
                self?.model.popoverOpen = false
            }
        }
        HotKey.action = { [weak self] in
            guard self?.model.recordingShortcut == false else { return }
            NSApp.activate()
            self?.toggle()
        }
        model.openSettings = { [weak self] in
            guard let self else { return }
            if settingsWindow == nil {
                settingsWindow = AppWindow(title: "Macpeek Settings") { SettingsView(model: self.model) }
            }
            settingsWindow?.show()
            popover.performClose(nil)
        }
        observe()
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            DispatchQueue.main.async { self.showWelcome() }
        }
    }

    private func showWelcome() {
        let window = AppWindow(title: "Welcome to Macpeek", plainTitlebar: true) { [unowned self] in
            WelcomeView(model: model) { [weak self] in
                self?.welcomeWindow?.close()
                // Show the real thing right where it lives.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.toggle() }
            }
        }
        window.onClose = { UserDefaults.standard.set(true, forKey: "didShowWelcome") }
        welcomeWindow = window
        window.show()
    }

    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func update() {
        let taken = !hotKey.register(model.shortcut)
        // Only write on change; every write re-triggers this observation.
        if model.shortcutTaken != taken { model.shortcutTaken = taken }
        render()
    }

    /// Only redraws when something visible changed: the item re-lays out on every new image.
    private func render() {
        let state = MenuBarGraph.State(
            cpu: Int((model.cpu.total * 100).rounded()),
            ram: Int(((model.memory?.pressureFraction ?? 0) * 100).rounded()),
            pressure: model.memory?.pressure ?? .normal,
            network: model.showNetwork
                ? .init(top: "↓ " + Format.rate(model.network.download), bottom: "↑ " + Format.rate(model.network.upload))
                : nil,
            disk: model.showDisk
                ? model.disk.map { .init(top: "F: " + Format.bytes($0.free), bottom: "U: " + Format.bytes($0.used)) }
                : nil,
            colored: model.coloredMenuBar
        )
        guard state != rendered, let button = item.button else { return }
        rendered = state
        button.image = MenuBarGraph.image(state)
        let summary = spokenSummary()
        button.toolTip = summary
        button.setAccessibilityLabel("Macpeek")
        button.setAccessibilityValue(summary)
    }

    private func spokenSummary() -> String {
        var parts = ["CPU \(Format.percent(model.cpu.total))"]
        if let memory = model.memory { parts.append("Memory pressure \(Format.percent(memory.pressureFraction))") }
        parts.append(model.vpn.connected ? "VPN on" : "VPN off")
        return parts.joined(separator: ", ")
    }

    private func fitPopover() {
        guard hosting.rootView.visible else { return }
        resizePopover(height: hosting.sizeThatFits(in: NSSize(width: 320, height: 10_000)).height)
    }

    private func resizePopover(height: CGFloat) {
        let size = NSSize(width: 320, height: height.rounded(.up))
        if popover.contentSize != size { popover.contentSize = size }
    }

    @objc private func clicked() {
        guard let event = NSApp.currentEvent else { return toggle() }
        let control = event.type == .leftMouseUp && event.modifierFlags.contains(.control)
        event.type == .rightMouseUp || control ? showMenu() : toggle()
    }

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Macpeek", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Run Full Test", action: #selector(runFullTest), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Macpeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Setting the menu only for this click keeps a left click opening the popover.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() {
        model.openSettings?()
    }

    @objc private func runFullTest() {
        Task { await model.runFullTest() }
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // A click on the icon first closes the popover (it's outside it), then fires this
            // action; reopening right away would make it flicker, so treat it as the close.
            guard Date.now.timeIntervalSince(lastClosed) > 0.3 else { return }
            model.popoverOpen = true
            setPopoverContent(visible: true)
            fitPopover()
            // Without this the first click inside the popover only activates the app.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            watchOutsideClicks()
        }
    }

    /// Set on the hosting view directly, so the next measurement already sees the new content.
    private func setPopoverContent(visible: Bool) {
        guard hosting.rootView.visible != visible else { return }
        hosting.rootView = PopoverView(model: model, visible: visible) { [weak self] height in
            self?.resizePopover(height: height)
        }
    }

    private func watchOutsideClicks() {
        stopWatchingOutsideClicks()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
    }

    private func stopWatchingOutsideClicks() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }
}
