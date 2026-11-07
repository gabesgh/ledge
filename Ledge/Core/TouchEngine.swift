import AppKit
import IOKit

/// One finger on the glass, in trackpad-relative coordinates.
struct TouchContact {
    let id: Int32
    let x: Double        // 0 = left edge, 1 = right edge
    let y: Double        // 0 = top edge (far from you), 1 = bottom edge
    let size: Float
    let majorAxis: Float
    let minorAxis: Float
}

struct TrackpadInfo: Equatable {
    let key: Int         // the MTDeviceRef's address, unique while the device lives
    let deviceID: UInt64
    let builtIn: Bool
    let familyID: Int32
    let widthMM: Double
    let heightMM: Double
}

struct TouchFrame {
    let device: TrackpadInfo
    let contacts: [TouchContact]
    let receivedAt: CFTimeInterval
}

private func contactFrameCallback(_ device: MTDeviceRef?,
                                  _ touches: UnsafePointer<MTTouch>?,
                                  _ count: Int32,
                                  _ timestamp: Double,
                                  _ frame: Int32) {
    TouchEngine.shared.receive(device: device, touches: touches, count: Int(count))
}

/// Reads raw finger positions from every Apple trackpad through the private
/// MultitouchSupport framework. Frames arrive on the framework's own thread.
final class TouchEngine {
    static let shared = TouchEngine()

    /// Called for every frame, on the multitouch thread. Set once at launch.
    var frameHandler: ((TouchFrame) -> Void)?

    private let lock = NSLock()
    private var deviceList: CFMutableArray?
    private var devices: [MTDeviceRef] = []
    private var infos: [Int: TrackpadInfo] = [:]
    private var latest: [Int: TouchFrame] = [:]
    private var lastTouched: Int?

    private var notifyPort: IONotificationPortRef?
    private var matchIterators: [io_iterator_t] = []
    private var restartWork: DispatchWorkItem?

    private init() {}

    // MARK: Lifecycle

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopDevices()

        guard let list = MTDeviceCreateList() else { return }
        var started: [MTDeviceRef] = []
        var found: [Int: TrackpadInfo] = [:]

        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            guard let info = describe(device) else { continue }
            found[info.key] = info
            started.append(device)
        }

        lock.lock()
        deviceList = list
        devices = started
        infos = found
        latest.removeAll()
        lastTouched = nil
        lock.unlock()

        for device in started {
            MTRegisterContactFrameCallback(device, contactFrameCallback)
            MTDeviceStart(device, 0)
        }

        installObserversOnce()
        DebugLog.write("trackpads: " + found.values.map {
            String(format: "%@ %.0f×%.0f mm (family %d)", $0.builtIn ? "built-in" : "external", $0.widthMM, $0.heightMM, $0.familyID)
        }.joined(separator: ", "))
        NotificationCenter.default.post(name: .ledgeTrackpadsChanged, object: nil)
    }

    private func stopDevices() {
        lock.lock()
        let old = devices
        devices = []
        infos = [:]
        latest = [:]
        lastTouched = nil
        let oldList = deviceList
        deviceList = nil
        lock.unlock()

        // Never hold the lock here: stopping waits for the callback thread. The
        // list owns the devices, so it has to outlive the calls.
        withExtendedLifetime(oldList) {
            for device in old {
                MTUnregisterContactFrameCallback(device, contactFrameCallback)
                if MTDeviceIsRunning(device) { MTDeviceStop(device) }
            }
        }
    }

    /// Restart a little later, coalescing bursts of wake / plug notifications.
    func scheduleRestart(after delay: TimeInterval = 1.0) {
        DispatchQueue.main.async {
            self.restartWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.start() }
            self.restartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func describe(_ device: MTDeviceRef) -> TrackpadInfo? {
        var family: Int32 = 0
        _ = MTDeviceGetFamilyID(device, &family)
        // Magic Mouse surfaces show up as multitouch devices too.
        if family == 112 || family == 113 { return nil }

        var width: Int32 = 0, height: Int32 = 0
        _ = MTDeviceGetSensorSurfaceDimensions(device, &width, &height)
        let widthMM = width > 0 ? Double(width) / 100 : 130
        let heightMM = height > 0 ? Double(height) / 100 : 85
        // Anything this small is a mouse or a Touch Bar, not a trackpad.
        guard widthMM >= 80, heightMM >= 40 else { return nil }

        var deviceID: UInt64 = 0
        _ = MTDeviceGetDeviceID(device, &deviceID)

        return TrackpadInfo(key: Int(bitPattern: device),
                            deviceID: deviceID,
                            builtIn: MTDeviceIsBuiltIn(device),
                            familyID: family,
                            widthMM: widthMM,
                            heightMM: heightMM)
    }

    // MARK: Frames

    fileprivate func receive(device: MTDeviceRef?, touches: UnsafePointer<MTTouch>?, count: Int) {
        guard let device else { return }
        let key = Int(bitPattern: device)

        var contacts: [TouchContact] = []
        if let touches, count > 0 {
            contacts.reserveCapacity(count)
            for i in 0..<count {
                let touch = touches[i]
                // 3 = make touch, 4 = touching. Hovering and lifting fingers don't count.
                guard touch.state == 3 || touch.state == 4 else { continue }
                contacts.append(TouchContact(
                    id: touch.pathIndex,
                    x: clamp(Double(touch.normalized.position.x)),
                    y: clamp(1 - Double(touch.normalized.position.y)),
                    size: touch.zTotal,
                    majorAxis: touch.majorAxis,
                    minorAxis: touch.minorAxis))
            }
        }

        lock.lock()
        guard let info = infos[key] else { lock.unlock(); return }
        let frame = TouchFrame(device: info, contacts: contacts, receivedAt: CACurrentMediaTime())
        latest[key] = frame
        if !contacts.isEmpty { lastTouched = key }
        let handler = frameHandler
        lock.unlock()

        handler?(frame)
    }

    /// The freshest frame from whichever trackpad currently has fingers on it.
    /// With two trackpads connected, the one you touch is in charge.
    func currentFrame(maxAge: CFTimeInterval = 0.25) -> TouchFrame? {
        lock.lock(); defer { lock.unlock() }
        let now = CACurrentMediaTime()
        let candidates = latest.values.filter { !$0.contacts.isEmpty && now - $0.receivedAt <= maxAge }
        return candidates.max { $0.receivedAt < $1.receivedAt }
    }

    /// For the live preview: the last trackpad touched, or the built-in one.
    func previewFrame() -> (TrackpadInfo?, [TouchContact]) {
        lock.lock(); defer { lock.unlock() }
        let now = CACurrentMediaTime()
        if let key = lastTouched, let frame = latest[key] {
            let fresh = now - frame.receivedAt < 0.2
            return (frame.device, fresh ? frame.contacts : [])
        }
        let fallback = infos.values.first { $0.builtIn } ?? infos.values.first
        return (fallback, [])
    }

    var trackpads: [TrackpadInfo] {
        lock.lock(); defer { lock.unlock() }
        return Array(infos.values)
    }

    // MARK: Hot-plug and sleep

    private var observersInstalled = false

    private func installObserversOnce() {
        guard !observersInstalled else { return }
        observersInstalled = true

        // Devices stop reporting across sleep; bring them back on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRestart(after: 1.5) }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRestart(after: 1.0) }

        // A Magic Trackpad connecting or disconnecting.
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

        let callback: IOServiceMatchingCallback = { refcon, iterator in
            drain(iterator)
            TouchEngine.shared.scheduleRestart(after: 1.0)
        }

        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), callback, nil, &iterator)
            if result == KERN_SUCCESS {
                drain(iterator)   // arms the notification
                matchIterators.append(iterator)
            }
        }
    }
}

private func drain(_ iterator: io_iterator_t) {
    var service = IOIteratorNext(iterator)
    while service != 0 {
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
}

@inline(__always) private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

extension Notification.Name {
    static let ledgeTrackpadsChanged = Notification.Name("LedgeTrackpadsChanged")
    static let ledgeGesturePerformed = Notification.Name("LedgeGesturePerformed")
    static let ledgeStatusChanged = Notification.Name("LedgeStatusChanged")
}
