#if DEBUG
import AppKit
import MacpeekCore
import SwiftUI

/// `MacpeekApp --snapshots <dir>` renders the menu bar item and popover to PNGs, so the UI can
/// be reviewed from CI without a Mac.
@MainActor
enum Snapshots {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel()
        model.loadSample()
        let history = model.cpuHistory.values.map { Int(($0 * 100).rounded()) }
        let all = MenuBarGraph.State(cpu: history, ram: 69, pressure: .normal,
                                     network: .init(top: "↓ 1.2 MB/s", bottom: "↑ 86.0 KB/s"),
                                     disk: .init(top: "F: 366.4 GB", bottom: "U: 127.9 GB"), vpn: true)
        var colored = all
        colored.colored = true
        let states: [(String, MenuBarGraph.State)] = [
            ("default", .init(cpu: history, ram: 69, pressure: .normal, network: nil, disk: nil, vpn: true)),
            ("all", all),
            ("colored", colored),
            ("vpn-off", .init(cpu: history, ram: 69, pressure: .normal, network: nil, disk: nil, vpn: false)),
            ("pressure", .init(cpu: history.map { min(100, $0 * 3) }, ram: 94, pressure: .critical,
                               network: nil, disk: nil, vpn: false)),
        ]
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            guard let appearance = NSAppearance(named: name) else { continue }
            for (label, state) in states {
                write(menuBar(state, appearance: appearance), to: directory.appending(path: "menubar-\(label)-\(suffix).png"))
            }
            let popover = PopoverView(model: model, visible: true)
                .background(Color(nsColor: .windowBackgroundColor))
            write(view(popover, appearance: appearance), to: directory.appending(path: "popover-\(suffix).png"))
            let settings = SettingsView(model: model)
                .background(Color(nsColor: .windowBackgroundColor))
            write(view(settings, appearance: appearance), to: directory.appending(path: "settings-\(suffix).png"))
            let welcome = WelcomeView(model: model) {}
                .background(Color(nsColor: .windowBackgroundColor))
            write(view(welcome, appearance: appearance), to: directory.appending(path: "welcome-\(suffix).png"))
        }
    }

    /// The item on a plain menu-bar-coloured strip, at 4x so it's easy to inspect.
    private static func menuBar(_ state: MenuBarGraph.State, appearance: NSAppearance) -> NSBitmapImageRep? {
        let image = MenuBarGraph.image(state)
        let padding: CGFloat = 8
        let size = NSSize(width: image.size.width + padding * 2, height: 24)
        let scale: CGFloat = 4
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
            NSRect(origin: .zero, size: size).fill()
            let target = NSRect(x: padding, y: (size.height - image.size.height) / 2,
                                width: image.size.width, height: image.size.height)
            if image.isTemplate {
                // What the menu bar does: keep the alpha, paint it in the label colour.
                let context = NSGraphicsContext.current?.cgContext
                context?.beginTransparencyLayer(in: target, auxiliaryInfo: nil)
                image.draw(in: target)
                NSColor.labelColor.set()
                target.fill(using: .sourceAtop)
                context?.endTransparencyLayer()
            } else {
                image.draw(in: target)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Hosts the view in an offscreen window so AppKit-backed controls render too.
    private static func view(_ content: some View, appearance: NSAppearance) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: content)
        hosting.appearance = appearance
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now + 0.5)
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep?, to url: URL) {
        guard let data = rep?.representation(using: .png, properties: [:]) else {
            print("Couldn't render \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
        print("Wrote \(url.lastPathComponent)")
    }
}
#endif
