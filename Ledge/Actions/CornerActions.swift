import AppKit

/// Counts clicks on a top corner and runs the action bound to that count.
/// With only a 1-click action the response is immediate; when a higher count is
/// also bound, Ledge waits a moment to see whether another click follows.
final class CornerClicks {
    static let shared = CornerClicks()

    private let window: TimeInterval = 0.42
    private var corner: Corner?
    private var count = 0
    private var lastClick: CFTimeInterval = 0
    private var pendingFire: (corner: Corner, clicks: Int, binding: CornerBinding)?
    private var pendingWork: DispatchWorkItem?

    private init() {}

    /// Main thread only.
    func click(_ corner: Corner, binding: CornerBinding) {
        let now = CACurrentMediaTime()
        if corner == self.corner, now - lastClick < window {
            count = min(count + 1, 4)
        } else {
            firePending()          // a different corner settles the previous one
            self.corner = corner
            count = 1
        }
        lastClick = now
        cancelPending()

        let clicks = count
        guard binding.hasAction(above: clicks) else {
            fire(corner, clicks: clicks, binding: binding)
            return
        }
        pendingFire = (corner, clicks, binding)
        let work = DispatchWorkItem { [weak self] in self?.firePending() }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + window, execute: work)
    }

    private func cancelPending() {
        pendingWork?.cancel()
        pendingWork = nil
        pendingFire = nil
    }

    private func firePending() {
        let waiting = pendingFire
        cancelPending()
        if let waiting { fire(waiting.corner, clicks: waiting.clicks, binding: waiting.binding) }
    }

    private func fire(_ corner: Corner, clicks: Int, binding: CornerBinding) {
        self.corner = nil
        count = 0
        guard let action = binding.action(forClicks: clicks) else { return }
        CornerActionRunner.run(action)
        NotificationCenter.default.post(name: .ledgeGesturePerformed, object: nil,
                                        userInfo: ["corner": corner.rawValue, "clicks": clicks])
    }
}

enum CornerActionRunner {
    static func run(_ action: CornerAction) {
        switch action.kind {
        case .none:
            break
        case .mute:
            SystemKeys.tap(.mute)
        case .playPause:
            SystemKeys.tap(.play)
        case .nextTrack:
            SystemKeys.tap(.next)
        case .previousTrack:
            SystemKeys.tap(.previous)
        case .openApp:
            toggleApp(at: action.path)
        case .openURL:
            open(link: action.url, browserPath: action.browserPath)
        case .openFile:
            guard !action.path.isEmpty else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: action.path))
        case .keyCombo:
            if let combo = action.combo { SystemKeys.press(combo) }
        case .shortcut:
            runShortcut(named: action.shortcutName)
        }
    }

    /// Opens the app, or hides it if it's already in front.
    private static func toggleApp(at path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleURL?.standardizedFileURL == url {
            front.hide()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func open(link: String, browserPath: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url: URL?
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        } else if trimmed.contains("://") || trimmed.hasPrefix("mailto:") {
            url = URL(string: trimmed)
        } else {
            url = URL(string: "https://" + trimmed)
        }
        guard let url else { return }

        guard !browserPath.isEmpty, url.scheme?.hasPrefix("http") == true else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: browserPath), configuration: configuration)
    }

    private static func runShortcut(named name: String) {
        guard !name.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    /// Names from the Shortcuts app, for the picker.
    static func availableShortcuts(completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var names: [String] = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                names = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            DispatchQueue.main.async { completion(names) }
        }
    }

    /// Installed web browsers, for the "open link in" picker.
    static func browsers() -> [URL] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .sorted { $0.deletingPathExtension().lastPathComponent < $1.deletingPathExtension().lastPathComponent }
    }
}

/// Ready-made key combinations for the corner editor.
enum KeyComboPreset: CaseIterable, Identifiable {
    case screenshot, screenshotSelection, screenshotToolbar, missionControl, appWindows, lockScreen, spotlight

    var id: String { title }

    var title: String {
        switch self {
        case .screenshot: return "Screenshot (whole screen)"
        case .screenshotSelection: return "Screenshot (selection)"
        case .screenshotToolbar: return "Screenshot toolbar"
        case .missionControl: return "Mission Control"
        case .appWindows: return "App windows"
        case .lockScreen: return "Lock screen"
        case .spotlight: return "Spotlight"
        }
    }

    var combo: KeyCombo {
        let cmd = CGEventFlags.maskCommand.rawValue
        let shift = CGEventFlags.maskShift.rawValue
        let ctrl = CGEventFlags.maskControl.rawValue
        switch self {
        case .screenshot: return KeyCombo(keyCode: 20, modifiers: cmd | shift, display: "⇧⌘3")
        case .screenshotSelection: return KeyCombo(keyCode: 21, modifiers: cmd | shift, display: "⇧⌘4")
        case .screenshotToolbar: return KeyCombo(keyCode: 23, modifiers: cmd | shift, display: "⇧⌘5")
        case .missionControl: return KeyCombo(keyCode: 126, modifiers: ctrl, display: "⌃↑")
        case .appWindows: return KeyCombo(keyCode: 125, modifiers: ctrl, display: "⌃↓")
        case .lockScreen: return KeyCombo(keyCode: 12, modifiers: ctrl | cmd, display: "⌃⌘Q")
        case .spotlight: return KeyCombo(keyCode: 49, modifiers: cmd, display: "⌘Space")
        }
    }
}
