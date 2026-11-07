import AppKit

/// An active event tap on left-button mouse events, running on its own thread so
/// a busy main thread can never make macOS time it out.
final class EventInterceptor {
    static let shared = EventInterceptor()

    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    private init() {}

    var isRunning: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Fails until Ledge has Accessibility permission.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else { return false }
        self.tap = tap

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            self?.runLoop = CFRunLoopGetCurrent()
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.gshimoon.ledge.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        self.thread = thread
        DebugLog.write("tap: running")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let runLoop { CFRunLoopStop(runLoop) }
        self.tap = nil
        runLoop = nil
        thread = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

private func eventTapCallback(proxy: CGEventTapProxy,
                              type: CGEventType,
                              event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        DebugLog.write(type == .tapDisabledByTimeout ? "tap: disabled by timeout, re-enabling" : "tap: disabled by user input, re-enabling")
        EventInterceptor.shared.reenable()
        GestureEngine.shared.reset()
        return Unmanaged.passUnretained(event)
    default:
        break
    }

    // Our own replays and key presses go straight through.
    if event.getIntegerValueField(.eventSourceUserData) == SystemKeys.marker {
        return Unmanaged.passUnretained(event)
    }

    let swallow = GestureEngine.shared.handleMouse(type: type, event: event, proxy: proxy)
    return swallow ? nil : Unmanaged.passUnretained(event)
}
