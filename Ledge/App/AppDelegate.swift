import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        TouchEngine.shared.frameHandler = { frame in
            GestureEngine.shared.handle(frame: frame)
        }
        TouchEngine.shared.start()

        NotificationCenter.default.addObserver(forName: .ledgeTrackpadsChanged, object: nil, queue: .main) { _ in
            Haptics.shared.reset()
        }

        EventInterceptor.shared.start()     // fails quietly until permission is granted
        AppStatus.shared.startMonitoring()

        statusItem = StatusItemController()
        Prefs.shared.$settings
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] visible in self?.statusItem?.setVisible(visible) }
            .store(in: &cancellables)

        let settings = Prefs.shared.settings
        if !settings.onboardingDone || !Permissions.accessibilityGranted {
            WindowManager.shared.showOnboarding()
        }
    }

    /// Opening Ledge again (Finder, Spotlight) brings up Settings — the way back
    /// in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        GestureEngine.shared.reset()
        EventInterceptor.shared.stop()
    }
}
