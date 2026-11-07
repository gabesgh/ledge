import AppKit

/// A light tick under the finger, played by the Force Touch actuator of the
/// trackpad that's being touched. Falls back to NSHapticFeedbackManager.
final class Haptics {
    static let shared = Haptics()

    private let queue = DispatchQueue(label: "com.gshimoon.ledge.haptics", qos: .userInteractive)
    private var actuators: [UInt64: MTActuator] = [:]
    private var failed: Set<UInt64> = []

    private init() {}

    func tick(deviceID: UInt64?, strength: HapticStrength? = nil) {
        let strength = strength ?? Prefs.shared.snapshot.haptics
        guard strength != .off else { return }

        queue.async {
            if let deviceID, let actuator = self.actuator(for: deviceID),
               MTActuatorActuate(actuator, strength.actuationID, 0, 0, 2) == kIOReturnSuccess {
                return
            }
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    /// Drop cached actuators, e.g. after the trackpads were re-enumerated.
    func reset() {
        queue.async {
            for actuator in self.actuators.values where MTActuatorIsOpen(actuator) {
                MTActuatorClose(actuator)
            }
            self.actuators.removeAll()
            self.failed.removeAll()
        }
    }

    private func actuator(for deviceID: UInt64) -> MTActuator? {
        if let cached = actuators[deviceID] { return cached }
        guard deviceID != 0, !failed.contains(deviceID) else { return nil }
        guard let actuator = MTActuatorCreateFromDeviceID(deviceID),
              MTActuatorOpen(actuator) == kIOReturnSuccess else {
            failed.insert(deviceID)
            return nil
        }
        actuators[deviceID] = actuator
        return actuator
    }
}
