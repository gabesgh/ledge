import AppKit

/// Turns "a physical click that lands in an edge strip, then a slide" into
/// volume, brightness and timeline control.
///
/// Mouse events arrive on the event-tap thread and touch frames on the
/// multitouch thread; all state lives behind one lock, and side effects run
/// after it's released.
final class GestureEngine {
    static let shared = GestureEngine()

    private struct Slide {
        let token: Int
        let role: EdgeRole
        let device: TrackpadInfo
        let contactID: Int32
        let startX: Double
        let startY: Double
        let cursor: CGPoint
        let downEvent: CGEvent
        let startedAt = CACurrentMediaTime()
        var anchor = 0.0          // millimetres of travel where the last step happened
        var direction = 0         // +1 up, -1 down, 0 before the first step
        var moved = false
        var cancelled = false

        // Timeline only.
        var lookup: MediaLookup?
        var origin: Double?
        var target: Double?
        var tickBucket: Int?
        var shownLoading = false
    }

    private enum Phase {
        case idle
        case slide(Slide)
        case corner          // swallowing the rest of a corner click
        case passthrough     // a replayed click macOS now owns until mouse-up
    }

    private typealias Effect = () -> Void

    private let lock = NSLock()
    /// Cursor calls talk to the window server. Making them from inside the event
    /// tap callback (while the window server waits on that callback) stalls the
    /// tap until macOS disables it, so they run here instead, in order.
    private let cursorQueue = DispatchQueue(label: "com.gshimoon.ledge.cursor", qos: .userInteractive)
    private var phase: Phase = .idle
    private var nextToken = 0
    private var cursorFrozen = false
    private var brightnessAvailable = SystemLevels.hasBuiltInDisplay
    private var lastLanding: (device: Int, contact: Int32)?
    private var problemShownAt: [String: CFTimeInterval] = [:]

    /// Reversing direction needs this fraction of a step, so a finger resting on
    /// a boundary can't flicker the level up and down.
    private static let reverseFraction = 0.6
    /// Only show "looking for something playing" if the lookup is actually slow.
    private static let loadingDelay: CFTimeInterval = 0.25

    private init() {
        // Warped cursors otherwise ignore the mouse for a quarter of a second.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshDisplays() }
    }

    func refreshDisplays() {
        let available = SystemLevels.hasBuiltInDisplay
        lock.lock(); brightnessAvailable = available; lock.unlock()
    }

    var hasBrightness: Bool {
        lock.lock(); defer { lock.unlock() }
        return brightnessAvailable
    }

    /// The edge being slid right now, for the live preview.
    var activeRole: EdgeRole? {
        lock.lock(); defer { lock.unlock() }
        if case .slide(let slide) = phase, !slide.cancelled { return slide.role }
        return nil
    }

    /// Abandon whatever is in progress and give the pointer back.
    func reset() {
        lock.lock()
        phase = .idle
        unfreezeCursor(warpTo: nil)
        lock.unlock()
        SeekHUD.shared.hide()
    }

    // MARK: Mouse events (event-tap thread)

    /// Returns true when the event should be swallowed.
    func handleMouse(type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> Bool {
        var effects: [Effect] = []
        lock.lock()
        let swallow: Bool
        switch type {
        case .leftMouseDown:
            swallow = mouseDown(event, effects: &effects)
        case .leftMouseDragged:
            switch phase {
            case .slide, .corner: swallow = true
            case .idle, .passthrough: swallow = false
            }
        case .leftMouseUp:
            swallow = mouseUp(event, proxy: proxy, effects: &effects)
        default:
            swallow = false
        }
        lock.unlock()
        effects.forEach { $0() }
        return swallow
    }

    private func mouseDown(_ event: CGEvent, effects: inout [Effect]) -> Bool {
        if case .slide = phase {            // a mouse-up went missing
            unfreezeCursor(warpTo: nil)
        }
        phase = .idle

        let settings = Prefs.shared.snapshot
        guard settings.enabled else { return false }
        if let required = settings.modifier.flag, !event.flags.contains(required) { return false }

        // Exactly one finger, and it has to be the one that clicked. Palms,
        // two-finger clicks and resting thumbs all fall through to macOS.
        guard let frame = TouchEngine.shared.currentFrame(),
              frame.contacts.count == 1,
              let contact = frame.contacts.first else {
            let count = TouchEngine.shared.currentFrame()?.contacts.count ?? 0
            DebugLog.write("down: ignored, \(count) finger(s) on the glass")
            return false
        }

        let map = ZoneMap(settings: settings, brightnessAvailable: brightnessAvailable)
        let position = String(format: "x=%.3f y=%.3f", contact.x, contact.y)
        guard let zone = map.zone(atX: contact.x, y: contact.y) else {
            DebugLog.write("down: \(position) middle, passed through")
            return false
        }
        DebugLog.write("down: \(position) \(zone) on \(frame.device.builtIn ? "built-in" : "external") pad")

        switch zone {
        case .corner(let corner):
            phase = .corner
            let binding = settings.binding(for: corner)
            effects.append { DispatchQueue.main.async { CornerClicks.shared.click(corner, binding: binding) } }
            return true

        case .edge(let role):
            guard let down = event.copy() else { return false }
            nextToken += 1
            let slide = Slide(token: nextToken, role: role, device: frame.device, contactID: contact.id,
                              startX: contact.x, startY: contact.y, cursor: event.location, downEvent: down)
            phase = .slide(slide)
            freezeCursor()
            if role == .media {
                let token = slide.token
                effects.append {
                    MediaController.shared.lookup(maxAge: 1.0) { [weak self] result in
                        self?.mediaArrived(result, token: token)
                    }
                }
            }
            return true
        }
    }

    private func mouseUp(_ event: CGEvent, proxy: CGEventTapProxy, effects: inout [Effect]) -> Bool {
        switch phase {
        case .idle:
            return false
        case .passthrough:
            phase = .idle
            return false
        case .corner:
            phase = .idle
            return true
        case .slide(let slide):
            phase = .idle
            DebugLog.write("up: \(slide.role.rawValue) moved=\(slide.moved) cancelled=\(slide.cancelled) anchor=\(String(format: "%.1f", slide.anchor))mm")

            guard slide.moved || slide.cancelled else {
                // A plain click that happened to land on an edge: hand it to macOS.
                unfreezeCursor(warpTo: nil)
                replayClick(down: slide.downEvent, up: event, proxy: proxy)
                if slide.role == .media { effects.append { SeekHUD.shared.hide() } }
                return true
            }

            unfreezeCursor(warpTo: slide.cursor)
            if slide.role == .media {
                if !slide.cancelled, case .found(let snapshot)? = slide.lookup, let target = slide.target {
                    effects.append {
                        MediaController.shared.seek(snapshot, to: target)
                        SeekHUD.shared.commit()
                    }
                } else {
                    effects.append { SeekHUD.shared.hide() }
                }
            }
            if !slide.cancelled {
                let role = slide.role
                effects.append {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .ledgeGesturePerformed, object: nil,
                                                        userInfo: ["edge": role.rawValue])
                    }
                }
            }
            return true
        }
    }

    private func replayClick(down: CGEvent, up: CGEvent, proxy: CGEventTapProxy) {
        guard let up = up.copy() else { return }
        down.setIntegerValueField(.eventSourceUserData, value: SystemKeys.marker)
        up.setIntegerValueField(.eventSourceUserData, value: SystemKeys.marker)
        down.tapPostEvent(proxy)
        up.tapPostEvent(proxy)
    }

    // MARK: Touch frames (multitouch thread)

    func handle(frame: TouchFrame) {
        var effects: [Effect] = []
        lock.lock()
        switch phase {
        case .slide(let slide) where slide.device.key == frame.device.key:
            phase = advance(slide, frame: frame, settings: Prefs.shared.snapshot, effects: &effects)
        case .idle:
            noticeLanding(frame, effects: &effects)
        default:
            break
        }
        lock.unlock()
        effects.forEach { $0() }
    }

    /// A finger resting on the bottom strip is a hint a seek may follow.
    private func noticeLanding(_ frame: TouchFrame, effects: inout [Effect]) {
        guard frame.contacts.count == 1, let contact = frame.contacts.first else {
            if frame.contacts.isEmpty { lastLanding = nil }
            return
        }
        let settings = Prefs.shared.snapshot
        guard settings.enabled, settings.mediaEnabled, contact.y > 1 - settings.edgeWidth else { return }
        if let last = lastLanding, last.device == frame.device.key, last.contact == contact.id { return }
        lastLanding = (frame.device.key, contact.id)
        effects.append { MediaController.shared.prefetch() }
    }

    private func advance(_ slide: Slide, frame: TouchFrame, settings: Settings, effects: inout [Effect]) -> Phase {
        var slide = slide
        guard !slide.cancelled,
              let contact = frame.contacts.first(where: { $0.id == slide.contactID }) else { return .slide(slide) }

        let map = ZoneMap(settings: settings, brightnessAvailable: brightnessAvailable)
        guard map.contains(slide.role, x: contact.x, y: contact.y) else {
            DebugLog.write(String(format: "slide: left the %@ strip at x=%.3f y=%.3f", slide.role.rawValue, contact.x, contact.y))
            if !slide.moved { return passThrough(slide, effects: &effects) }
            // Leaving the strip ends the slide where it is; a seek is called off.
            slide.cancelled = true
            if slide.role == .media { effects.append { SeekHUD.shared.cancel() } }
            return .slide(slide)
        }

        switch slide.role {
        case .volume, .brightness:
            // A ratchet: every step needs a full step of travel in the same
            // direction, or most of one to turn back.
            let travel = (slide.startY - contact.y) * frame.device.heightMM   // up is positive
            var delta = 0
            while true {
                let diff = travel - slide.anchor
                let direction = diff >= 0 ? 1 : -1
                let needed = (slide.direction == 0 || direction == slide.direction)
                    ? settings.stepMillimetres
                    : settings.stepMillimetres * Self.reverseFraction
                guard abs(diff) >= needed else { break }
                slide.anchor += Double(direction) * needed
                slide.direction = direction
                delta += direction
            }
            if delta != 0 {
                DebugLog.write(String(format: "step: %@ %+d (travel %.1f mm)", slide.role.rawValue, delta, travel))
                slide.moved = true
                let role = slide.role, deviceID = frame.device.deviceID
                effects.append { GestureEngine.step(role, delta: delta, deviceID: deviceID) }
            }

        case .media:
            let dx = contact.x - slide.startX
            if !slide.moved, abs(dx) < settings.seekDeadzone { break }

            guard let lookup = slide.lookup else {
                if !slide.shownLoading, CACurrentMediaTime() - slide.startedAt > Self.loadingDelay {
                    slide.shownLoading = true
                    effects.append { SeekHUD.shared.loading() }
                }
                break
            }

            // The lookup lands once per slide and only `.found` sets `moved`, so
            // the first two cases always arrive before anything happened.
            switch lookup {
            case .nothing:
                // Nothing to scrub, so this was an ordinary drag.
                return passThrough(slide, effects: &effects)

            case .problem(let message):
                // Something the user can fix (a permission, a browser setting).
                // Say so now and then, but never hold an ordinary drag hostage.
                let now = CACurrentMediaTime()
                if now - (problemShownAt[message] ?? 0) > 30 {
                    problemShownAt[message] = now
                    effects.append { SeekHUD.shared.problem(message) }
                }
                return passThrough(slide, effects: &effects)

            case .found(let snapshot):
                slide.moved = true
                let origin = slide.origin ?? snapshot.position()
                slide.origin = origin
                let span = settings.seekSpan.seconds(forDuration: snapshot.duration)
                let target = min(max(origin + dx * span, 0), snapshot.duration)
                slide.target = target

                let bucket = Int((target / max(span / 32, 1)).rounded(.down))
                if let previous = slide.tickBucket, previous != bucket {
                    let deviceID = frame.device.deviceID
                    effects.append { Haptics.shared.tick(deviceID: deviceID) }
                }
                slide.tickBucket = bucket
                effects.append { SeekHUD.shared.preview(snapshot, origin: origin, target: target) }
            }
        }
        return .slide(slide)
    }

    /// The finger left before doing anything: it was a click-and-drag all along.
    /// Put the pointer back, replay the press, and let macOS have the rest.
    private func passThrough(_ slide: Slide, effects: inout [Effect]) -> Phase {
        unfreezeCursor(warpTo: slide.cursor)
        let down = slide.downEvent
        down.setIntegerValueField(.eventSourceUserData, value: SystemKeys.marker)
        effects.append { down.post(tap: .cghidEventTap) }
        if slide.role == .media { effects.append { SeekHUD.shared.hide() } }
        return .passthrough
    }

    private func mediaArrived(_ lookup: MediaLookup, token: Int) {
        lock.lock()
        if case .slide(var slide) = phase, slide.token == token {
            slide.lookup = lookup
            phase = .slide(slide)
        }
        lock.unlock()
    }

    // MARK: Effects

    private static func step(_ role: EdgeRole, delta: Int, deviceID: UInt64) {
        let up = delta > 0
        let key: SystemKey
        switch role {
        case .volume: key = up ? .soundUp : .soundDown
        case .brightness: key = up ? .brightnessUp : .brightnessDown
        case .media: return
        }
        if SystemLevels.canStep(role, up: up) {
            Haptics.shared.tick(deviceID: deviceID)
        }
        SystemKeys.tap(key, fine: SystemKeys.fineModifiersHeld, times: abs(delta))
    }

    /// The pointer stays put while you slide. Caller holds the lock; the actual
    /// window-server calls are queued and run after the lock and callback return.
    private func freezeCursor() {
        guard !cursorFrozen else { return }
        cursorFrozen = true
        cursorQueue.async {
            let result = CGAssociateMouseAndMouseCursorPosition(0)
            if result != .success { DebugLog.write("cursor freeze failed: \(result.rawValue)") }
        }
    }

    private func unfreezeCursor(warpTo point: CGPoint?) {
        guard cursorFrozen else { return }
        cursorFrozen = false
        cursorQueue.async {
            if let point { CGWarpMouseCursorPosition(point) }
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }
}
