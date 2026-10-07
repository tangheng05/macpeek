import AppKit
import SwiftUI

/// A window for a menu-bar-only app. While any is open the app acts like a regular app
/// (Dock icon, ⌘-Tab), because macOS often won't bring an accessory app's window forward.
@MainActor
final class AppWindow: NSObject, NSWindowDelegate {
    private static var openCount = 0
    private var window: NSWindow?
    private let title: String
    private let makeContent: () -> AnyView

    init(title: String, content: @escaping () -> some View) {
        self.title = title
        self.makeContent = { AnyView(content()) }
    }

    var isOpen: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        if !isOpen { Self.openCount += 1 }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        Self.openCount = max(0, Self.openCount - 1)
        if Self.openCount == 0 { NSApp.setActivationPolicy(.accessory) }
        // A closed window's views would keep updating with the model, so build it fresh next time.
        DispatchQueue.main.async { [weak self] in
            guard self?.isOpen == false else { return }
            self?.window = nil
        }
    }
}
