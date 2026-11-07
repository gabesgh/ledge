import AppKit
import ApplicationServices
import ServiceManagement

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Ledge to the Accessibility list.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            DebugLog.write("login item change failed: \(error.localizedDescription)")
        }
    }
}

/// Live status for the menu and settings: permission, event tap, trackpads.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    @Published private(set) var interceptorRunning = false
    @Published private(set) var trackpads: [TrackpadInfo] = []
    @Published private(set) var brightnessAvailable = SystemLevels.hasBuiltInDisplay

    private var timer: Timer?

    private init() {}

    func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        NotificationCenter.default.addObserver(forName: .ledgeTrackpadsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    private func tick() {
        let granted = Permissions.accessibilityGranted
        if granted, !EventInterceptor.shared.isRunning {
            EventInterceptor.shared.start()
        }
        refresh()
    }

    func refresh() {
        let granted = Permissions.accessibilityGranted
        let running = EventInterceptor.shared.isRunning
        let pads = TouchEngine.shared.trackpads.sorted { $0.builtIn && !$1.builtIn }
        let brightness = SystemLevels.hasBuiltInDisplay
        let changed = granted != accessibilityGranted || running != interceptorRunning
            || pads != trackpads || brightness != brightnessAvailable
        guard changed else { return }
        accessibilityGranted = granted
        interceptorRunning = running
        trackpads = pads
        brightnessAvailable = brightness
        NotificationCenter.default.post(name: .ledgeStatusChanged, object: nil)
    }

    var isWorking: Bool { accessibilityGranted && interceptorRunning && !trackpads.isEmpty }

    var summary: String {
        if !accessibilityGranted { return "Needs Accessibility access" }
        if !interceptorRunning { return "Starting…" }
        if trackpads.isEmpty { return "No trackpad found" }
        return Prefs.shared.settings.enabled ? "Active" : "Paused"
    }
}

extension TrackpadInfo {
    var displayName: String {
        if builtIn { return "Built-in trackpad" }
        return "Magic Trackpad"
    }

    var sizeDescription: String {
        String(format: "%.0f × %.0f mm", widthMM, heightMM)
    }
}
