import AppKit
import SwiftUI

/// Click, then type a key combination. Escape cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Type a shortcut…" : (combo?.display ?? "Record Shortcut"))
                .monospacedDigit()
                .frame(minWidth: 130)
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            if event.keyCode == 53, flags.isEmpty {   // Escape
                stop()
                return nil
            }
            // NSEvent and CGEvent use the same bits for these modifiers.
            combo = KeyCombo(keyCode: event.keyCode,
                             modifiers: UInt64(flags.rawValue),
                             display: ShortcutRecorder.describe(event, flags: flags))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    static func describe(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> String {
        var text = ""
        if flags.contains(.function) { text += "fn " }
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyName(event)
    }

    private static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        if let special = specialKeys[event.keyCode] { return special }
        let base = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "?"
        return base.uppercased()
    }
}
