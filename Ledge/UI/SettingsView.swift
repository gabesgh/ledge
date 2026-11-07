import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            GesturesTab()
                .tabItem { Label("Gestures", systemImage: "hand.draw") }
            CornersTab()
                .tabItem { Label("Corners", systemImage: "square.grid.2x2") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 680, minHeight: 560)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var status = AppStatus.shared
    @State private var launchAtLogin = LoginItem.enabled

    var body: some View {
        Form {
            Section {
                TrackpadPreview()
                    .frame(maxWidth: .infinity, maxHeight: 230)
                    .padding(.vertical, 6)
                Text("Touch the trackpad to see the zones light up. Press an edge until it clicks, then slide.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                LabeledContent("Accessibility") {
                    if status.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
                LabeledContent("Trackpads") {
                    if status.trackpads.isEmpty {
                        Text("None found").foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(status.trackpads, id: \.key) { pad in
                                Text("\(pad.displayName) · \(pad.sizeDescription)")
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("Enable Ledge", isOn: $prefs.settings.enabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in LoginItem.set(value) }
                Picker("Menu bar icon", selection: $prefs.settings.menuBarIcon) {
                    ForEach(MenuBarIconMode.allCases) { Text($0.title).tag($0) }
                }
                if prefs.settings.menuBarIcon != .always {
                    Text("Open Ledge again from Applications or Spotlight to bring the icon and these settings back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Feel") {
                Picker("Haptic tick on each step", selection: $prefs.settings.haptics) {
                    ForEach(HapticStrength.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Try it") {
                    Button("Play Tick") {
                        let pad = status.trackpads.first { $0.builtIn } ?? status.trackpads.first
                        let strength = prefs.settings.haptics == .off ? HapticStrength.light : prefs.settings.haptics
                        Haptics.shared.tick(deviceID: pad?.deviceID, strength: strength)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Gestures

private struct GesturesTab: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var status = AppStatus.shared

    var body: some View {
        Form {
            Section {
                TrackpadPreview()
                    .frame(maxWidth: .infinity, maxHeight: 170)
                    .padding(.vertical, 4)
            }

            Section("Edges") {
                Toggle(isOn: $prefs.settings.volumeEnabled) {
                    Label("Volume · \(side(.volume)) edge", systemImage: EdgeRole.volume.symbol)
                }
                Toggle(isOn: $prefs.settings.brightnessEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Brightness · \(side(.brightness)) edge", systemImage: EdgeRole.brightness.symbol)
                        if !status.brightnessAvailable {
                            Text("Needs the built-in display, so it stays off on a closed MacBook or a desktop Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: $prefs.settings.mediaEnabled) {
                    Label("Media timeline · bottom edge", systemImage: EdgeRole.media.symbol)
                }
                Toggle("Swap sides", isOn: $prefs.settings.swapSides)
            }

            Section("Feel") {
                LabeledContent("Edge width") {
                    HStack {
                        Slider(value: $prefs.settings.edgeWidth, in: 0.05...0.20, step: 0.01)
                            .frame(width: 220)
                        Text("\(Int((prefs.settings.edgeWidth * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Slide per step") {
                    HStack {
                        Slider(value: $prefs.settings.stepMillimetres, in: 1.5...6, step: 0.1)
                            .frame(width: 220)
                        Text(String(format: "%.1f mm", prefs.settings.stepMillimetres))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Picker("Side edges respond on", selection: $prefs.settings.sideRange) {
                    ForEach(SideRange.allCases) { Text($0.title).tag($0) }
                }
                Picker("Only while holding", selection: $prefs.settings.modifier) {
                    ForEach(ModifierRequirement.allCases) { Text($0.title).tag($0) }
                }
                Text("Volume and brightness move in the same 16 steps as the keys. Hold ⇧⌥ while sliding for quarter steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Timeline") {
                Picker("Sliding the full width covers", selection: $prefs.settings.seekSpan) {
                    ForEach(SeekSpan.allCases) { Text($0.title).tag($0) }
                }
                Text("Press the bottom edge, slide sideways, and let go to jump. Works with Music, Spotify, QuickTime Player, VLC, and videos in Safari, Chrome, Arc, Brave, Edge and Vivaldi. Browsers need “Allow JavaScript from Apple Events” turned on in their Developer menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Automation Settings…") { Permissions.openAutomationSettings() }
            }
        }
        .formStyle(.grouped)
    }

    private func side(_ role: EdgeRole) -> String {
        prefs.settings.role(isLeftEdge: true) == role ? "left" : "right"
    }
}

// MARK: - Corners

private struct CornersTab: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                Text("Give each top corner a job. Click once, or up to four times for less common actions. A corner with nothing set stays a normal part of the trackpad.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Corner.allCases) { corner in
                Section(corner.title) {
                    ForEach(0..<4, id: \.self) { index in
                        CornerActionEditor(clicks: index + 1, action: binding(corner, index))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ corner: Corner, _ index: Int) -> Binding<CornerAction> {
        corner == .topLeft ? $prefs.settings.topLeft.actions[index] : $prefs.settings.topRight.actions[index]
    }
}

struct CornerActionEditor: View {
    let clicks: Int
    @Binding var action: CornerAction
    @State private var shortcuts: [String] = []
    @State private var browsers: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(clicks == 1 ? "1 click" : "\(clicks) clicks", selection: $action.kind) {
                ForEach(CornerAction.Kind.allCases) { Text($0.title).tag($0) }
            }
            detail
        }
    }

    @ViewBuilder private var detail: some View {
        switch action.kind {
        case .openApp:
            HStack {
                if !action.path.isEmpty {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: action.path))
                        .resizable().frame(width: 18, height: 18)
                    Text(FileManager.default.displayName(atPath: action.path))
                } else {
                    Text("No app chosen").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose App…") { chooseApp() }
            }
            Text("Click again while it's in front to hide it.").font(.caption).foregroundStyle(.secondary)

        case .openURL:
            TextField("Link", text: $action.url, prompt: Text("claude.ai"))
            Picker("Open in", selection: $action.browserPath) {
                Text("Default browser").tag("")
                ForEach(browsers, id: \.path) { url in
                    Text(FileManager.default.displayName(atPath: url.path)).tag(url.path)
                }
            }
            .onAppear {
                if browsers.isEmpty { browsers = CornerActionRunner.browsers() }
            }

        case .openFile:
            HStack {
                Text(action.path.isEmpty ? "Nothing chosen" : FileManager.default.displayName(atPath: action.path))
                    .foregroundStyle(action.path.isEmpty ? .secondary : .primary)
                Spacer()
                Button("Choose…") { chooseFile() }
            }

        case .keyCombo:
            HStack {
                ShortcutRecorder(combo: $action.combo)
                Menu("Presets") {
                    ForEach(KeyComboPreset.allCases) { preset in
                        Button("\(preset.title)  \(preset.combo.display)") { action.combo = preset.combo }
                    }
                }
                .fixedSize()
            }

        case .shortcut:
            Picker("Shortcut", selection: $action.shortcutName) {
                Text("Choose a shortcut").tag("")
                ForEach(shortcutChoices, id: \.self) { Text($0).tag($0) }
            }
            .onAppear {
                CornerActionRunner.availableShortcuts { shortcuts = $0 }
            }

        default:
            EmptyView()
        }
    }

    private var shortcutChoices: [String] {
        var names = shortcuts
        if !action.shortcutName.isEmpty, !names.contains(action.shortcutName) { names.insert(action.shortcutName, at: 0) }
        return names
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { action.path = url.path }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { action.path = url.path }
    }
}

// MARK: - About

private struct AboutTab: View {
    @ObservedObject private var prefs = Prefs.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ledge").font(.title2.bold())
                        Text(version).foregroundStyle(.secondary)
                        Text("Four new controls on the trackpad you already have.")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("How it works") {
                AboutRow(symbol: "hand.tap", text: "A gesture starts only when one finger lands inside an edge strip and physically clicks. Palms, typing, scrolling and clicks elsewhere are left alone.")
                AboutRow(symbol: "cursorarrow", text: "While you slide, the pointer stays put. A click on an edge that doesn't slide is passed straight on to macOS.")
                AboutRow(symbol: "lock.shield", text: "Touches never leave your Mac. Ledge makes no network requests.")
                AboutRow(symbol: "bolt", text: "A native Swift menu bar app, idle unless your finger is on the trackpad.")
            }

            Section("Troubleshooting") {
                Toggle("Write a diagnostic log", isOn: $prefs.settings.diagnosticLog)
                if prefs.settings.diagnosticLog {
                    LabeledContent("Each click and slide is noted in ~/Library/Logs/Ledge.") {
                        Button("Show Log in Finder") {
                            DebugLog.write("log opened")
                            NSWorkspace.shared.activateFileViewerSelecting([DebugLog.fileURL])
                        }
                    }
                    .font(.callout)
                }
                Button("Open Welcome Guide…") { WindowManager.shared.showOnboarding() }
                Button("Reset All Settings", role: .destructive) { prefs.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
