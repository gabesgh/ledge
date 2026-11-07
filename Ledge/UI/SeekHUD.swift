import AppKit
import SwiftUI

final class SeekHUDModel: ObservableObject {
    enum Mode { case loading, preview, committed, cancelled, problem }

    @Published var mode: Mode = .loading
    @Published var appName = ""
    @Published var title = ""
    @Published var subtitle = ""
    @Published var duration: Double = 0
    @Published var origin: Double = 0
    @Published var target: Double = 0
    @Published var message = ""
}

/// The floating "release to jump" preview shown while sliding along the bottom edge.
final class SeekHUD {
    static let shared = SeekHUD()

    private let model = SeekHUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    private init() {}

    func loading() {
        onMain {
            self.model.mode = .loading
            self.model.title = "Looking for something playing…"
            self.model.subtitle = ""
            self.present()
        }
    }

    func preview(_ snapshot: MediaSnapshot, origin: Double, target: Double) {
        onMain {
            let m = self.model
            m.mode = .preview
            m.appName = snapshot.appName
            m.title = snapshot.title
            m.subtitle = snapshot.subtitle.isEmpty ? snapshot.appName : "\(snapshot.subtitle) · \(snapshot.appName)"
            m.duration = snapshot.duration
            m.origin = origin
            m.target = target
            self.present()
        }
    }

    func problem(_ message: String) {
        onMain {
            self.model.mode = .problem
            self.model.title = "Can't reach the player"
            self.model.subtitle = ""
            self.model.message = message
            self.present()
        }
    }

    func commit() {
        onMain {
            self.model.mode = .committed
            self.dismiss(after: 0.9)
        }
    }

    func cancel() {
        onMain {
            guard self.panel?.isVisible == true else { return }
            self.model.mode = .cancelled
            self.dismiss(after: 0.6)
        }
    }

    /// Hide now, except an error message, which stays long enough to read.
    func hide() {
        onMain {
            self.dismiss(after: self.model.mode == .problem ? 3.0 : 0)
        }
    }

    // MARK: Panel

    private func present() {
        hideWork?.cancel()
        hideWork = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func dismiss(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel, panel.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: SeekHUDView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: SeekHUDView.width, height: 112)
        let panel = NSPanel(contentRect: host.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: true)
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 96)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}

struct SeekHUDView: View {
    static let width: CGFloat = 380
    @ObservedObject var model: SeekHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !model.subtitle.isEmpty {
                        Text(model.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if model.mode == .preview || model.mode == .committed {
                    Text(deltaText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            switch model.mode {
            case .problem:
                Text(model.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            case .loading:
                SeekBar(duration: 1, origin: 0, target: 0, dimmed: true)
            default:
                SeekBar(duration: model.duration, origin: model.origin, target: model.target,
                        dimmed: model.mode == .cancelled)
                HStack {
                    Text("\(formatTime(model.target)) / \(formatTime(model.duration))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .foregroundStyle(.white)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var icon: String {
        switch model.mode {
        case .problem: return "exclamationmark.triangle.fill"
        case .committed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        default: return model.target >= model.origin ? "goforward" : "gobackward"
        }
    }

    private var hint: String {
        switch model.mode {
        case .committed: return "Jumped"
        case .cancelled: return "Cancelled"
        default: return "Release to jump"
        }
    }

    private var deltaText: String {
        let delta = model.target - model.origin
        return (delta >= 0 ? "+" : "−") + formatTime(abs(delta))
    }
}

private struct SeekBar: View {
    let duration: Double
    let origin: Double
    let target: Double
    let dimmed: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(duration, 1)
            let targetX = width * min(max(target / total, 0), 1)
            let originX = width * min(max(origin / total, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(.white.opacity(dimmed ? 0.35 : 0.95))
                    .frame(width: max(targetX, 6))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 12)
                    .offset(x: originX - 1)
                    .opacity(dimmed ? 0 : 1)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.08), value: target)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
