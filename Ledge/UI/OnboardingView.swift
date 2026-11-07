import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @ObservedObject private var status = AppStatus.shared
    @ObservedObject private var prefs = Prefs.shared
    @State private var step = 0
    @State private var tried: Set<String> = []

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permission
                case 2: corner
                default: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 44)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0...lastStep, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                if step == 1, !status.accessibilityGranted {
                    Button("Skip for Now") { step += 1 }
                }
                Button(step == lastStep ? "Done" : "Continue") {
                    if step == lastStep { finish() } else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && !status.accessibilityGranted)
            }
            .padding(16)
        }
        .frame(width: 640, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: .ledgeGesturePerformed)) { note in
            if let edge = note.userInfo?["edge"] as? String { tried.insert(edge) }
            if let corner = note.userInfo?["corner"] as? String { tried.insert(corner) }
        }
    }

    private func finish() {
        prefs.settings.onboardingDone = true
        onFinish()
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            Text("One trackpad. Four new controls.")
                .font(.system(size: 26, weight: .bold))
            Text("Press an edge of your trackpad until it clicks, then slide. The right edge sets the volume, the left edge sets brightness, the bottom edge scrubs whatever is playing, and the top corners run your shortcuts. The middle works exactly as before.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TrackpadPreview()
                .frame(maxWidth: 420, maxHeight: 240)
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Allow Accessibility")
                .font(.system(size: 24, weight: .bold))
            Text("Ledge needs one permission. With it, Ledge can press the volume and brightness keys for you, and keep clicks on the edges out of your apps while you slide. It never records what you type, and nothing leaves your Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                HStack(spacing: 14) {
                    Image(systemName: status.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(status.accessibilityGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(status.accessibilityGranted ? "Accessibility is on" : "Accessibility is off")
                            .font(.headline)
                        Text(status.accessibilityGranted
                             ? "You're all set. Continue to pick a corner shortcut."
                             : "Open System Settings, then switch on Ledge under Privacy & Security › Accessibility.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !status.accessibilityGranted {
                        Button("Open System Settings") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
                .padding(8)
            }
            Text("This page updates by itself once the switch is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var corner: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your top-right corner")
                .font(.system(size: 24, weight: .bold))
            Text("The top-left corner mutes. What should a click on the top-right corner do? You can set up to four click counts per corner later in Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(CornerChoice.allCases) { choice in
                    Button { apply(choice) } label: {
                        HStack {
                            Image(systemName: choice.symbol).frame(width: 22)
                            Text(choice.title)
                            Spacer()
                            if isSelected(choice) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected(choice) ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
                }
            }

            if prefs.settings.topRight.actions[0].kind == .openApp {
                CornerActionEditor(clicks: 1, action: $prefs.settings.topRight.actions[0])
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try it on your trackpad")
                .font(.system(size: 24, weight: .bold))
            Text("Press each edge until it clicks, then slide. Each one gets a tick when it works.")
                .foregroundStyle(.secondary)

            TrackpadPreview()
                .frame(maxWidth: .infinity, maxHeight: 230)

            VStack(alignment: .leading, spacing: 8) {
                checkRow("Right edge: slide up and down for volume", key: prefs.settings.swapSides ? "brightness" : "volume")
                if status.brightnessAvailable {
                    checkRow("Left edge: slide for brightness", key: prefs.settings.swapSides ? "volume" : "brightness")
                }
                checkRow("Bottom edge: slide sideways to scrub, let go to jump", key: "media")
                checkRow("Top-left corner: click to mute", key: Corner.topLeft.rawValue)
            }
        }
    }

    private func checkRow(_ text: String, key: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tried.contains(key) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(tried.contains(key) ? .green : .secondary)
                .font(.system(size: 16))
            Text(text)
        }
    }

    // MARK: Corner choice

    private enum CornerChoice: CaseIterable, Identifiable {
        case nothing, screenshot, missionControl, playPause, lockScreen, openApp
        var id: Self { self }

        var title: String {
            switch self {
            case .nothing: return "Nothing — keep it a normal part of the trackpad"
            case .screenshot: return "Take a screenshot of a selection"
            case .missionControl: return "Show Mission Control"
            case .playPause: return "Play or pause"
            case .lockScreen: return "Lock the screen"
            case .openApp: return "Open an app…"
            }
        }

        var symbol: String {
            switch self {
            case .nothing: return "circle.dashed"
            case .screenshot: return "camera.viewfinder"
            case .missionControl: return "rectangle.3.group"
            case .playPause: return "playpause.fill"
            case .lockScreen: return "lock.fill"
            case .openApp: return "app.badge"
            }
        }

        var action: CornerAction {
            var action = CornerAction()
            switch self {
            case .nothing: break
            case .screenshot: action.kind = .keyCombo; action.combo = KeyComboPreset.screenshotSelection.combo
            case .missionControl: action.kind = .keyCombo; action.combo = KeyComboPreset.missionControl.combo
            case .playPause: action.kind = .playPause
            case .lockScreen: action.kind = .keyCombo; action.combo = KeyComboPreset.lockScreen.combo
            case .openApp: action.kind = .openApp
            }
            return action
        }
    }

    private func apply(_ choice: CornerChoice) {
        var binding = CornerBinding()
        binding.actions[0] = choice.action
        prefs.settings.topRight = binding
    }

    private func isSelected(_ choice: CornerChoice) -> Bool {
        let current = prefs.settings.topRight
        let first = current.actions[0]
        let othersEmpty = !current.actions.dropFirst().contains { $0.isSet }
        guard othersEmpty else { return false }
        switch choice {
        case .openApp: return first.kind == .openApp
        default:
            let wanted = choice.action
            return first.kind == wanted.kind && first.combo == wanted.combo
        }
    }
}
