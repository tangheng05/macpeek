import Foundation
import IOKit.ps
import MacpeekCore
import SystemConfiguration

/// Fires when the routing, DNS or tunnel setup changes. No polling: the dynamic store pushes it.
@MainActor
final class NetworkWatcher {
    private var store: SCDynamicStore?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let watcher = Unmanaged<NetworkWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange() }
        }
        guard let store = SCDynamicStoreCreate(nil, "Macpeek" as CFString, callback, &context) else { return }
        SCDynamicStoreSetNotificationKeys(store, nil, VPNDetector.watchedPatterns as CFArray)
        SCDynamicStoreSetDispatchQueue(store, .main)
        self.store = store
    }
}

/// Fires when the battery level, charger or power source changes.
@MainActor
final class PowerWatcher {
    private var source: CFRunLoopSource?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let callback: IOPowerSourceCallbackType = { info in
            guard let info else { return }
            let watcher = Unmanaged<PowerWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?
            .takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }
}
