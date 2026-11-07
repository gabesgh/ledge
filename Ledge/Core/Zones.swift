import Foundation

enum Zone: Equatable {
    case edge(EdgeRole)
    case corner(Corner)
}

/// Trackpad geometry. Coordinates are fractions of the surface with the origin
/// at the top-left (the far corner from you).
struct ZoneMap {
    let settings: Settings
    let brightnessAvailable: Bool

    /// How far past its strip a finger may wander before the slide counts as left.
    static let exitTolerance = 1.6

    func zone(atX x: Double, y: Double) -> Zone? {
        let s = settings

        // Corners win, but only if they have something to do. An empty corner
        // stays part of the edge strip or the ordinary trackpad.
        if y < s.cornerHeight {
            if x < s.cornerWidth, !s.topLeft.isEmpty { return .corner(.topLeft) }
            if x > 1 - s.cornerWidth, !s.topRight.isEmpty { return .corner(.topRight) }
        }

        // The bottom strip owns the bottom corners.
        if y > 1 - s.edgeWidth {
            return s.mediaEnabled ? .edge(.media) : nil
        }

        let inSideRange = y >= 1 - s.sideRange.fraction
        if x < s.edgeWidth, inSideRange {
            return usable(s.role(isLeftEdge: true))
        }
        if x > 1 - s.edgeWidth, inSideRange {
            return usable(s.role(isLeftEdge: false))
        }
        return nil
    }

    private func usable(_ role: EdgeRole) -> Zone? {
        guard settings.isEnabled(role) else { return nil }
        if role == .brightness, !brightnessAvailable { return nil }
        return .edge(role)
    }

    /// True while a slide that began in `role`'s strip is still inside it.
    func contains(_ role: EdgeRole, x: Double, y: Double) -> Bool {
        let band = settings.edgeWidth * Self.exitTolerance
        switch role {
        case .media:
            return y > 1 - band
        case .volume, .brightness:
            let isLeft = settings.role(isLeftEdge: true) == role
            return isLeft ? x < band : x > 1 - band
        }
    }
}
