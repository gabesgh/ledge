import AppKit
import SwiftUI

final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Ledge Settings",
                                        size: NSSize(width: 720, height: 600),
                                        content: SettingsView())
        }
        present(settingsWindow)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(title: "Welcome to Ledge",
                                          size: NSSize(width: 640, height: 600),
                                          content: OnboardingView { [weak self] in self?.closeOnboarding() })
        }
        present(onboardingWindow)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.center()
        window.delegate = self
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == onboardingWindow {
            onboardingWindow = nil
            Prefs.shared.settings.onboardingDone = true
        }
        if window == settingsWindow {
            settingsWindow = nil
        }
    }
}
