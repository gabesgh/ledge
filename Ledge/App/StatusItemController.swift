import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let autoHideItem = NSMenuItem(title: "Auto-hide Menu Bar Icon", action: #selector(toggleAutoHide), keyEquivalent: "")

    /// How long the icon lingers after you leave Ledge, in auto-hide mode.
    private static let autoHideDelay: TimeInterval = 5
    private var mode: MenuBarIconMode = .always
    private var menuOpen = false
    private var hideWork: DispatchWorkItem?

    override init() {
        super.init()
        item.button?.image = StatusItemController.icon(active: true)
        item.button?.toolTip = "Ledge"
        item.autosaveName = "LedgeStatusItem"   // keeps its spot when it reappears

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Ledge", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "Ledge", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(header)
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        enabledItem.target = self
        menu.addItem(enabledItem)
        autoHideItem.target = self
        menu.addItem(autoHideItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Welcome Guide…", #selector(openGuide)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Ledge", #selector(quit), key: "q"))
        item.menu = menu

        NotificationCenter.default.addObserver(forName: .ledgeStatusChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateVisibility()
            }
        }
        refresh()
    }

    func apply(_ mode: MenuBarIconMode) {
        self.mode = mode
        autoHideItem.state = mode == .autoHide ? .on : .off
        updateVisibility()
    }

    /// In auto-hide mode the icon stays while Ledge is in front or its menu is
    /// open, and goes a few seconds after you move on.
    private func updateVisibility() {
        hideWork?.cancel()
        hideWork = nil

        switch mode {
        case .always:
            item.isVisible = true
        case .hidden:
            item.isVisible = false
        case .autoHide:
            if NSApp.isActive || menuOpen {
                item.isVisible = true
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.mode == .autoHide, !NSApp.isActive, !self.menuOpen else { return }
                self.item.isVisible = false
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoHideDelay, execute: work)
        }
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        AppStatus.shared.refresh()
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        updateVisibility()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        updateVisibility()
    }

    private func refresh() {
        let status = AppStatus.shared
        let enabled = Prefs.shared.settings.enabled
        statusLine.title = status.summary
        enabledItem.state = enabled ? .on : .off
        enabledItem.isEnabled = status.accessibilityGranted
        item.button?.image = StatusItemController.icon(active: enabled && status.isWorking)
    }

    @objc private func toggleEnabled() {
        Prefs.shared.settings.enabled.toggle()
        if !Prefs.shared.settings.enabled { GestureEngine.shared.reset() }
        refresh()
    }

    @objc private func toggleAutoHide() {
        let turningOn = Prefs.shared.settings.menuBarIcon != .autoHide
        Prefs.shared.settings.menuBarIcon = turningOn ? .autoHide : .always
        guard turningOn, !Prefs.shared.settings.autoHideExplained else { return }

        // Say once how to get the icon back, before it disappears.
        Prefs.shared.settings.autoHideExplained = true
        let alert = NSAlert()
        alert.messageText = "The menu bar icon will hide itself"
        alert.informativeText = "It disappears 5 seconds after you leave Ledge. To bring it back, open Ledge again from Spotlight or the Applications folder."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openSettings() { WindowManager.shared.showSettings() }
    @objc private func openGuide() { WindowManager.shared.showOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// A trackpad outline with its working edges drawn heavier.
    static func icon(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let pad = NSRect(x: 2, y: 3.5, width: 14, height: 11)
            let outline = NSBezierPath(roundedRect: pad, xRadius: 2.6, yRadius: 2.6)
            outline.lineWidth = 1.3
            NSColor.black.setStroke()
            outline.stroke()

            NSColor.black.withAlphaComponent(active ? 1 : 0.45).setFill()
            NSBezierPath(roundedRect: NSRect(x: 13.2, y: 6.8, width: 1.6, height: 5.4), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 3.2, y: 6.8, width: 1.6, height: 5.4), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 5.6, y: 4.7, width: 6.8, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
