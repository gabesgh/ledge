import AppKit
import Combine

enum EdgeRole: String, Codable, CaseIterable, Identifiable {
    case volume, brightness, media
    var id: String { rawValue }

    var title: String {
        switch self {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .media: return "Timeline"
        }
    }
}

enum Corner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight
    var id: String { rawValue }
    var title: String { self == .topLeft ? "Top-left corner" : "Top-right corner" }
}

enum SideRange: String, Codable, CaseIterable, Identifiable {
    case full, lowerHalf, lowerQuarter
    var id: String { rawValue }

    /// Fraction of the side edge, measured up from the bottom, where a slide may start.
    var fraction: Double {
        switch self {
        case .full: return 1
        case .lowerHalf: return 0.5
        case .lowerQuarter: return 0.25
        }
    }

    var title: String {
        switch self {
        case .full: return "Whole edge"
        case .lowerHalf: return "Bottom half"
        case .lowerQuarter: return "Bottom quarter"
        }
    }
}

enum ModifierRequirement: String, Codable, CaseIterable, Identifiable {
    case none, fn, control, option, command
    var id: String { rawValue }

    var flag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .fn: return .maskSecondaryFn
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .command: return .maskCommand
        }
    }

    var title: String {
        switch self {
        case .none: return "None"
        case .fn: return "fn"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        }
    }
}

enum HapticStrength: String, Codable, CaseIterable, Identifiable {
    case off, light, medium, strong
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Force Touch actuator waveforms (MultitouchSupport actuation IDs).
    var actuationID: Int32 {
        switch self {
        case .off, .light: return 3
        case .medium: return 4
        case .strong: return 6
        }
    }
}

enum SeekSpan: String, Codable, CaseIterable, Identifiable {
    case wholeTrack, tenMinutes, fiveMinutes, twoMinutes, oneMinute
    var id: String { rawValue }

    /// Seconds covered by sliding across the full width of the trackpad.
    func seconds(forDuration duration: Double) -> Double {
        switch self {
        case .wholeTrack: return max(duration, 1)
        case .tenMinutes: return 600
        case .fiveMinutes: return 300
        case .twoMinutes: return 120
        case .oneMinute: return 60
        }
    }

    var title: String {
        switch self {
        case .wholeTrack: return "Whole track"
        case .tenMinutes: return "10 minutes"
        case .fiveMinutes: return "5 minutes"
        case .twoMinutes: return "2 minutes"
        case .oneMinute: return "1 minute"
        }
    }
}

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64   // CGEventFlags raw value, device-independent bits only
    var display: String
}

struct CornerAction: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case none, mute, playPause, nextTrack, previousTrack, openApp, openURL, openFile, keyCombo, shortcut
        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "Nothing"
            case .mute: return "Mute"
            case .playPause: return "Play / Pause"
            case .nextTrack: return "Next track"
            case .previousTrack: return "Previous track"
            case .openApp: return "Open app"
            case .openURL: return "Open link"
            case .openFile: return "Open file or folder"
            case .keyCombo: return "Press keys"
            case .shortcut: return "Run Shortcut"
            }
        }
    }

    var kind: Kind = .none
    var path: String = ""          // app, file or folder
    var url: String = ""
    var browserPath: String = ""   // empty = default browser
    var combo: KeyCombo? = nil
    var shortcutName: String = ""

    var isSet: Bool { kind != .none }
}

/// What each top corner does for one, two, three and four clicks.
struct CornerBinding: Codable, Hashable {
    var actions: [CornerAction] = Array(repeating: CornerAction(), count: 4)

    var isEmpty: Bool { !actions.contains { $0.isSet } }

    func action(forClicks clicks: Int) -> CornerAction? {
        guard clicks >= 1, clicks <= actions.count else { return nil }
        let action = actions[clicks - 1]
        return action.isSet ? action : nil
    }

    func hasAction(above clicks: Int) -> Bool {
        guard clicks < actions.count else { return false }
        return actions[clicks...].contains { $0.isSet }
    }

    static var muteOnClick: CornerBinding {
        var binding = CornerBinding()
        binding.actions[0].kind = .mute
        return binding
    }
}

struct Settings: Codable, Equatable {
    var enabled = true

    // Geometry. Fractions of the trackpad; slides are measured in millimetres.
    var edgeWidth = 0.10
    var cornerWidth = 0.20
    var cornerHeight = 0.17
    var stepMillimetres = 3.4
    var seekDeadzone = 0.025

    var volumeEnabled = true
    var brightnessEnabled = true
    var mediaEnabled = true
    var swapSides = false
    var sideRange: SideRange = .full
    var modifier: ModifierRequirement = .none
    var seekSpan: SeekSpan = .wholeTrack
    var haptics: HapticStrength = .light

    var topLeft = CornerBinding.muteOnClick
    var topRight = CornerBinding()

    var showMenuBarIcon = true
    var onboardingDone = false
    var diagnosticLog = false

    func binding(for corner: Corner) -> CornerBinding {
        corner == .topLeft ? topLeft : topRight
    }

    func role(isLeftEdge: Bool) -> EdgeRole {
        (isLeftEdge != swapSides) ? .brightness : .volume
    }

    func isEnabled(_ role: EdgeRole) -> Bool {
        switch role {
        case .volume: return volumeEnabled
        case .brightness: return brightnessEnabled
        case .media: return mediaEnabled
        }
    }
}

/// The single source of truth for preferences. UI edits `settings`; the engine
/// reads `snapshot`, a lock-protected copy that's safe on any thread.
final class Prefs: ObservableObject {
    static let shared = Prefs()

    @Published var settings: Settings

    private static let storageKey = "LedgeSettings.v1"
    private let lock = NSLock()
    private var current: Settings
    private var cancellables = Set<AnyCancellable>()

    var snapshot: Settings {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    private init() {
        let loaded = Prefs.load()
        settings = loaded
        current = loaded

        $settings
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                self.lock.lock()
                self.current = value
                self.lock.unlock()
                Prefs.save(value)
            }
            .store(in: &cancellables)
    }

    func resetToDefaults() {
        var fresh = Settings()
        fresh.onboardingDone = settings.onboardingDone
        settings = fresh
    }

    /// Stored values laid over the defaults, so settings added later decode cleanly.
    private static func load() -> Settings {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let defaultsData = try? JSONEncoder().encode(Settings()),
            var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return Settings() }

        merged.merge(stored) { _, stored in stored }
        guard
            let mergedData = try? JSONSerialization.data(withJSONObject: merged),
            let settings = try? JSONDecoder().decode(Settings.self, from: mergedData)
        else { return Settings() }
        return settings
    }

    private static func save(_ settings: Settings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
