import AppKit
import AudioToolbox
import CoreAudio

/// Reads the current volume and built-in display brightness. Only used to stay
/// quiet (no haptic tick) when a slide pushes past the end of the range.
enum SystemLevels {

    // MARK: Volume

    static func outputVolume() -> (level: Float, muted: Bool)? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }

        var volume = Float32(0)
        size = UInt32(MemoryLayout<Float32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }

        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyMute
        if AudioObjectHasProperty(device, &address) {
            _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        }
        return (volume, muted != 0)
    }

    // MARK: Brightness

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    private static let getBrightness: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    /// The built-in panel, if it's lit. A closed lid or a desktop Mac has none.
    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var hasBuiltInDisplay: Bool { builtInDisplay != nil }

    static func builtInBrightness() -> Float? {
        guard let display = builtInDisplay, let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(display, &value) == 0 ? value : nil
    }

    /// Whether one more step in `direction` would change anything.
    static func canStep(_ role: EdgeRole, up: Bool) -> Bool {
        let level: Float?
        switch role {
        case .volume:
            guard let output = outputVolume() else { return true }
            if output.muted { return true }   // unmuting is a change
            level = output.level
        case .brightness:
            level = builtInBrightness()
        case .media:
            return true
        }
        guard let level else { return true }
        return up ? level < 0.999 : level > 0.001
    }
}
