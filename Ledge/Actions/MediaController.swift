import AppKit

/// Where a now-playing position came from, and therefore how to seek it.
enum MediaSource: Equatable {
    case mediaRemote                 // system now-playing, macOS 14 – 15.3
    case scripted(MediaPlayer)       // AppleScript, any macOS version
}

struct MediaSnapshot {
    let source: MediaSource
    let appName: String
    let title: String
    let subtitle: String
    let duration: Double
    let elapsed: Double
    let isPlaying: Bool
    let measuredAt: CFTimeInterval

    /// Where playback is right now, extrapolated from when it was measured.
    func position(at now: CFTimeInterval = CACurrentMediaTime()) -> Double {
        let drift = isPlaying ? max(0, now - measuredAt) : 0
        return min(max(elapsed + drift, 0), duration)
    }
}

enum MediaLookup {
    case found(MediaSnapshot)
    case nothing
    case problem(String)
}

/// A player Ledge can read and seek through its scripting interface.
struct MediaPlayer: Equatable {
    enum Kind: Equatable { case music, spotify, quickTime, vlc, safari, chromium }

    let bundleID: String
    let name: String
    let kind: Kind

    static let all: [MediaPlayer] = [
        MediaPlayer(bundleID: "com.apple.Music", name: "Music", kind: .music),
        MediaPlayer(bundleID: "com.spotify.client", name: "Spotify", kind: .spotify),
        MediaPlayer(bundleID: "com.apple.QuickTimePlayerX", name: "QuickTime Player", kind: .quickTime),
        MediaPlayer(bundleID: "org.videolan.vlc", name: "VLC", kind: .vlc),
        MediaPlayer(bundleID: "com.apple.Safari", name: "Safari", kind: .safari),
        MediaPlayer(bundleID: "com.google.Chrome", name: "Google Chrome", kind: .chromium),
        MediaPlayer(bundleID: "com.brave.Browser", name: "Brave", kind: .chromium),
        MediaPlayer(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", kind: .chromium),
        MediaPlayer(bundleID: "company.thebrowser.Browser", name: "Arc", kind: .chromium),
        MediaPlayer(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", kind: .chromium),
    ]
}

/// Finds what's playing and moves its playhead. Everything here runs off the
/// main thread; callers get results on an arbitrary queue.
final class MediaController {
    static let shared = MediaController()

    private let queue = DispatchQueue(label: "com.gshimoon.ledge.media", qos: .userInteractive)
    private let lock = NSLock()
    private var cached: (lookup: MediaLookup, at: CFTimeInterval)?
    private var waiters: [(MediaLookup) -> Void] = []
    private var inFlight = false
    private var lastPrefetch: CFTimeInterval = 0

    private init() {}

    /// In-process MediaRemote stopped answering third-party apps in macOS 15.4.
    private var mediaRemoteUsable: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion < 15 || (v.majorVersion == 15 && v.minorVersion < 4)
    }

    // MARK: Public

    /// Warm the cache when a finger lands on the bottom strip, before it clicks.
    func prefetch() {
        let now = CACurrentMediaTime()
        lock.lock()
        let recent = now - lastPrefetch < 3
        if !recent { lastPrefetch = now }
        lock.unlock()
        // Only the in-process path is cheap and silent. Scripting a player from a
        // mere touch could raise an Automation prompt before anyone clicked.
        guard !recent, mediaRemoteUsable else { return }
        lookup(maxAge: 1.0) { _ in }
    }

    func lookup(maxAge: CFTimeInterval = 1.0, completion: @escaping (MediaLookup) -> Void) {
        lock.lock()
        if let cached, CACurrentMediaTime() - cached.at <= maxAge {
            let value = cached.lookup
            lock.unlock()
            completion(value)
            return
        }
        waiters.append(completion)
        let shouldStart = !inFlight
        inFlight = true
        lock.unlock()

        guard shouldStart else { return }
        queue.async {
            let result = self.performLookup()
            self.lock.lock()
            self.cached = (result, CACurrentMediaTime())
            let callbacks = self.waiters
            self.waiters = []
            self.inFlight = false
            self.lock.unlock()
            callbacks.forEach { $0(result) }
        }
    }

    func seek(_ snapshot: MediaSnapshot, to seconds: Double) {
        let target = min(max(seconds, 0), snapshot.duration)
        invalidate()
        queue.async {
            switch snapshot.source {
            case .mediaRemote:
                MRMediaRemoteSetElapsedTime(target)
            case .scripted(let player):
                _ = Script.run(Script.seek(player, to: target))
            }
        }
    }

    func invalidate() {
        lock.lock(); cached = nil; lock.unlock()
    }

    // MARK: Lookup

    private func performLookup() -> MediaLookup {
        if mediaRemoteUsable, let snapshot = mediaRemoteSnapshot() {
            return .found(snapshot)
        }

        let players = runningPlayers()
        guard !players.isEmpty else { return .nothing }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Ask every running player at once; scripting round-trips are slow.
        var results = [Result<MediaSnapshot?, ScriptFailure>](repeating: .success(nil), count: players.count)
        let group = DispatchGroup()
        let resultsLock = NSLock()
        for (index, player) in players.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let result = Script.snapshot(of: player)
                resultsLock.lock(); results[index] = result; resultsLock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 2.5)

        resultsLock.lock()
        let found = zip(players, results).compactMap { player, result -> (MediaPlayer, MediaSnapshot)? in
            if case .success(let snapshot?) = result { return (player, snapshot) }
            return nil
        }
        let failures = results.compactMap { result -> ScriptFailure? in
            if case .failure(let failure) = result { return failure }
            return nil
        }
        resultsLock.unlock()

        // Playing beats paused; the frontmost app beats the rest.
        let ranked = found.sorted { a, b in
            if a.1.isPlaying != b.1.isPlaying { return a.1.isPlaying }
            return (a.0.bundleID == frontmost) && (b.0.bundleID != frontmost)
        }
        if let best = ranked.first { return .found(best.1) }
        if let failure = failures.first { return .problem(failure.message) }
        return .nothing
    }

    private func runningPlayers() -> [MediaPlayer] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return MediaPlayer.all.filter { running.contains($0.bundleID) }
    }

    private func mediaRemoteSnapshot() -> MediaSnapshot? {
        let done = DispatchSemaphore(value: 0)
        var snapshot: MediaSnapshot?
        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.global(qos: .userInteractive)) { ref in
            defer { done.signal() }
            guard let ref, let info = (ref as NSDictionary) as? [String: Any] else { return }
            func number(_ key: String) -> Double? { (info[key] as? NSNumber)?.doubleValue }
            guard let duration = number("kMRMediaRemoteNowPlayingInfoDuration"), duration > 0,
                  let elapsed = number("kMRMediaRemoteNowPlayingInfoElapsedTime") else { return }
            let rate = number("kMRMediaRemoteNowPlayingInfoPlaybackRate") ?? 0
            var measured = CACurrentMediaTime()
            if let stamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                measured -= max(0, Date().timeIntervalSince(stamp))
            }
            snapshot = MediaSnapshot(
                source: .mediaRemote,
                appName: "Now Playing",
                title: info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "Now Playing",
                subtitle: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                duration: duration,
                elapsed: elapsed,
                isPlaying: rate > 0,
                measuredAt: measured)
        }
        _ = done.wait(timeout: .now() + 0.8)
        return snapshot
    }
}

// MARK: - AppleScript

struct ScriptFailure: Error {
    let message: String
}

private enum Script {
    static let separator = "\t"

    /// Finds the media element a page is most likely playing.
    private static let findMedia =
        "var all=Array.prototype.slice.call(document.querySelectorAll('video,audio'));" +
        "var v=all.find(function(m){return !m.paused&&!m.ended;})||all.find(function(m){return m.currentTime>0;})||all[0];"

    private static let readJS =
        "(function(){" + findMedia +
        "if(!v||!isFinite(v.duration)||v.duration<=0)return 'none';" +
        "return [v.currentTime,v.duration,document.title,location.hostname,(v.paused?'paused':'playing')].join('\\t');})()"

    private static func seekJS(_ seconds: Double) -> String {
        "(function(){" + findMedia + "if(v){v.currentTime=\(seconds);}return 'ok';})()"
    }

    static func snapshot(of player: MediaPlayer) -> Result<MediaSnapshot?, ScriptFailure> {
        let started = CACurrentMediaTime()
        switch run(read(player)) {
        case .failure(let failure):
            // Only problems the user can fix are worth showing; anything else
            // (no track loaded, a page without video) just means "not playing".
            guard let advice = explain(failure.message, player: player) else { return .success(nil) }
            return .failure(ScriptFailure(message: advice))
        case .success(let output):
            let finished = CACurrentMediaTime()
            let fields = output.components(separatedBy: separator)
            guard fields.count >= 5,
                  let elapsed = number(fields[0]),
                  let duration = number(fields[1]), duration > 0, duration.isFinite else {
                return .success(nil)
            }
            let state = fields[4].lowercased()
            let playing = state.contains("playing") || state == "true"
            return .success(MediaSnapshot(
                source: .scripted(player),
                appName: player.name,
                title: fields[2].isEmpty ? player.name : fields[2],
                subtitle: fields[3],
                duration: duration,
                elapsed: elapsed,
                isPlaying: playing,
                measuredAt: (started + finished) / 2))
        }
    }

    private static func read(_ player: MediaPlayer) -> String {
        let app = "application id \"\(player.bundleID)\""
        switch player.kind {
        case .music:
            return """
            tell \(app)
                if player state is stopped then return "none"
                set t to current track
                return (player position as text) & tab & (duration of t as text) & tab & (name of t) & tab & (artist of t) & tab & (player state as text)
            end tell
            """
        case .spotify:
            return """
            tell \(app)
                if player state is stopped then return "none"
                set t to current track
                return (player position as text) & tab & ((duration of t) / 1000 as text) & tab & (name of t) & tab & (artist of t) & tab & (player state as text)
            end tell
            """
        case .quickTime:
            return """
            tell \(app)
                if (count of documents) is 0 then return "none"
                set d to document 1
                return (current time of d as text) & tab & (duration of d as text) & tab & (name of d) & tab & "" & tab & (playing of d as text)
            end tell
            """
        case .vlc:
            return """
            tell \(app)
                try
                    return (current time as text) & tab & (duration of current item as text) & tab & (name of current item) & tab & "" & tab & (playing as text)
                on error
                    return "none"
                end try
            end tell
            """
        case .safari:
            return """
            tell \(app)
                if (count of windows) is 0 then return "none"
                return do JavaScript "\(escape(readJS))" in current tab of front window
            end tell
            """
        case .chromium:
            return """
            tell \(app)
                if (count of windows) is 0 then return "none"
                return execute active tab of front window javascript "\(escape(readJS))"
            end tell
            """
        }
    }

    static func seek(_ player: MediaPlayer, to seconds: Double) -> String {
        let app = "application id \"\(player.bundleID)\""
        let value = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)
        switch player.kind {
        case .music, .spotify:
            return "tell \(app) to set player position to \(value)"
        case .quickTime:
            return "tell \(app) to set current time of document 1 to \(value)"
        case .vlc:
            return "tell \(app) to set current time to \(Int(seconds.rounded()))"
        case .safari:
            return "tell \(app) to do JavaScript \"\(escape(seekJS(seconds)))\" in current tab of front window"
        case .chromium:
            return "tell \(app) to execute active tab of front window javascript \"\(escape(seekJS(seconds)))\""
        }
    }

    /// Runs AppleScript in osascript, so a hung player can never stall Ledge.
    static func run(_ source: String, timeout: TimeInterval = 2.0) -> Result<String, ScriptFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch {
            return .failure(ScriptFailure(message: error.localizedDescription))
        }

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        let text = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(ScriptFailure(message: message))
        }
        return .success(text)
    }

    private static func explain(_ message: String, player: MediaPlayer) -> String? {
        if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
            return "Allow Ledge to control \(player.name) in System Settings › Privacy & Security › Automation."
        }
        if message.localizedCaseInsensitiveContains("javascript") {
            switch player.kind {
            case .safari:
                return "In Safari, turn on Develop › Allow JavaScript from Apple Events."
            default:
                return "In \(player.name), turn on View › Developer › Allow JavaScript from Apple Events."
            }
        }
        return nil
    }

    private static func escape(_ js: String) -> String {
        js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// AppleScript prints reals with the user's decimal separator.
    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
