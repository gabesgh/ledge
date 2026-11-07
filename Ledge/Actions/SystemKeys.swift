import AppKit

/// NX_KEYTYPE_* codes for the special keys on a Mac keyboard.
enum SystemKey: Int32 {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
}

/// Presses keys the way the keyboard would, so macOS takes the same steps and
/// shows its own volume and brightness indicator.
enum SystemKeys {
    static let marker: Int64 = 0x4C_45_44_47_45   // "LEDGE"
    private static let queue = DispatchQueue(label: "com.gshimoon.ledge.keys", qos: .userInteractive)

    /// `fine` adds ⇧⌥, which macOS turns into quarter steps.
    static func tap(_ key: SystemKey, fine: Bool = false, times: Int = 1) {
        guard times > 0 else { return }
        queue.async {
            for _ in 0..<times {
                post(key, down: true, fine: fine)
                post(key, down: false, fine: fine)
            }
        }
    }

    private static func post(_ key: SystemKey, down: Bool, fine: Bool) {
        var flags: UInt = down ? 0xA00 : 0xB00
        if fine {
            flags |= NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue
        }
        let data1 = (Int(key.rawValue) << 16) | ((down ? 0xA : 0xB) << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ), let cgEvent = event.cgEvent else { return }
        cgEvent.setIntegerValueField(.eventSourceUserData, value: marker)
        cgEvent.post(tap: .cghidEventTap)
    }

    /// Presses an ordinary key combination such as ⇧⌘4.
    static func press(_ combo: KeyCombo) {
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            let flags = CGEventFlags(rawValue: combo.modifiers)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down) else { continue }
                event.flags = flags
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// True while ⇧ and ⌥ are both held on the keyboard.
    static var fineModifiersHeld: Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskShift) && flags.contains(.maskAlternate)
    }
}
