import SwiftUI

/// A live picture of the trackpad you're touching: its zones, your fingers, and
/// which control would respond.
struct TrackpadPreview: View {
    @ObservedObject private var prefs = Prefs.shared
    var showLabels = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
            let (device, contacts) = TouchEngine.shared.previewFrame()
            let active = GestureEngine.shared.activeRole
            let brightness = GestureEngine.shared.hasBrightness
            let aspect = device.map { $0.widthMM / $0.heightMM } ?? 1.6

            VStack(spacing: 8) {
                Canvas { context, size in
                    TrackpadDrawing(settings: prefs.settings,
                                    brightnessAvailable: brightness,
                                    contacts: contacts,
                                    activeRole: active,
                                    showLabels: showLabels)
                        .draw(in: &context, size: size)
                }
                .aspectRatio(aspect, contentMode: .fit)

                Text(device.map { "\($0.displayName) · \($0.sizeDescription)" } ?? "No trackpad found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension EdgeRole {
    var color: Color {
        switch self {
        case .volume: return Color(red: 1.0, green: 0.42, blue: 0.22)
        case .brightness: return Color(red: 1.0, green: 0.78, blue: 0.2)
        case .media: return Color(red: 0.25, green: 0.72, blue: 1.0)
        }
    }

    var symbol: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .media: return "play.rectangle.fill"
        }
    }
}

private struct TrackpadDrawing {
    let settings: Settings
    let brightnessAvailable: Bool
    let contacts: [TouchContact]
    let activeRole: EdgeRole?
    let showLabels: Bool

    static let cornerColor = Color(red: 0.62, green: 0.48, blue: 1.0)

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let radius = min(size.width, size.height) * 0.07
        let pad = Path(roundedRect: bounds, cornerRadius: radius, style: .continuous)

        context.fill(pad, with: .linearGradient(
            Gradient(colors: [Color(white: 0.24), Color(white: 0.17)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        var clipped = context
        clipped.clip(to: pad)

        let map = ZoneMap(settings: settings, brightnessAvailable: brightnessAvailable)
        let hover: Zone? = contacts.count == 1 ? map.zone(atX: contacts[0].x, y: contacts[0].y) : nil

        for zone in zones() {
            let rect = self.rect(for: zone.zone, in: bounds)
            let lit = zone.zone == hover || activeRole.map { zone.zone == .edge($0) } == true
            let opacity = !zone.available ? 0.06 : (lit ? 0.55 : 0.2)
            clipped.fill(Path(rect), with: .color(zone.color.opacity(opacity)))
            if showLabels, zone.available {
                label(zone, in: rect, context: &clipped)
            }
        }

        context.stroke(pad, with: .color(.white.opacity(0.14)), lineWidth: 1)

        for contact in contacts {
            let center = CGPoint(x: bounds.minX + contact.x * bounds.width,
                                 y: bounds.minY + contact.y * bounds.height)
            let r = max(9, min(size.width * 0.045, 22))
            let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.fill(dot, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.95), .white.opacity(0.35)]),
                center: center, startRadius: 0, endRadius: r))
        }
    }

    private struct DrawnZone {
        let zone: Zone
        let color: Color
        let available: Bool
        let title: String
    }

    private func zones() -> [DrawnZone] {
        var result: [DrawnZone] = []
        for isLeft in [true, false] {
            let role = settings.role(isLeftEdge: isLeft)
            var available = settings.isEnabled(role)
            if role == .brightness, !brightnessAvailable { available = false }
            result.append(DrawnZone(zone: .edge(role), color: role.color, available: available, title: role.title))
        }
        result.append(DrawnZone(zone: .edge(.media), color: EdgeRole.media.color,
                                available: settings.mediaEnabled, title: EdgeRole.media.title))
        for corner in Corner.allCases where !settings.binding(for: corner).isEmpty {
            let first = settings.binding(for: corner).actions.first { $0.isSet }
            result.append(DrawnZone(zone: .corner(corner), color: Self.cornerColor,
                                    available: true, title: first?.kind.title ?? "Corner"))
        }
        return result
    }

    private func rect(for zone: Zone, in b: CGRect) -> CGRect {
        let s = settings
        let edgeW = b.width * s.edgeWidth
        let edgeH = b.height * s.edgeWidth
        let sideTop = b.minY + b.height * (1 - s.sideRange.fraction)
        let sideBottom = b.maxY - edgeH
        switch zone {
        case .edge(.media):
            return CGRect(x: b.minX, y: b.maxY - edgeH, width: b.width, height: edgeH)
        case .edge(let role):
            let isLeft = s.role(isLeftEdge: true) == role
            let x = isLeft ? b.minX : b.maxX - edgeW
            // A corner with an action takes priority over the top of its strip.
            let corner: Corner = isLeft ? .topLeft : .topRight
            let top = s.binding(for: corner).isEmpty ? sideTop : max(sideTop, b.minY + b.height * s.cornerHeight)
            return CGRect(x: x, y: top, width: edgeW, height: max(0, sideBottom - top))
        case .corner(let corner):
            let w = b.width * s.cornerWidth, h = b.height * s.cornerHeight
            let x = corner == .topLeft ? b.minX : b.maxX - w
            return CGRect(x: x, y: b.minY, width: w, height: h)
        }
    }

    private func label(_ zone: DrawnZone, in rect: CGRect, context: inout GraphicsContext) {
        let text = Text(zone.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.85))
        switch zone.zone {
        case .edge(.media), .corner:
            context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
        case .edge:
            var rotated = context
            rotated.translateBy(x: rect.midX, y: rect.midY)
            rotated.rotate(by: .degrees(-90))
            rotated.draw(text, at: .zero)
        }
    }
}
