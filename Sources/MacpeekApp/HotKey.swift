import Carbon
import Foundation
import MacpeekCore

/// A system-wide shortcut via Carbon's hot key API, which needs no Accessibility permission.
@MainActor
final class HotKey {
    static var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var current: KeyCombo?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.action?() } }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Returns false when another app already owns the combination.
    @discardableResult
    func register(_ combo: KeyCombo?) -> Bool {
        if combo == current, combo == nil || ref != nil { return true }
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        current = combo
        guard let combo else { return true }
        let id = EventHotKeyID(signature: OSType(0x4D50_4B4D), id: 1)
        return RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }
}
