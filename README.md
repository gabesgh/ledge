# Ledge

Volume, brightness, media scrubbing and shortcuts on the edges of your Mac trackpad. A from-scratch, open-source take on [MacEdge](https://macedge.site/), written in Swift as a menu bar app.

Press an edge of the trackpad until it clicks, then slide:

| Where | What it does |
| --- | --- |
| Right edge | System volume, in the same 16 steps as the volume keys, with the macOS indicator |
| Left edge | Built-in display brightness, same steps and indicator |
| Bottom edge | Scrub the media timeline: slide sideways, let go to jump |
| Top corners | 1–4 clicks each: mute, play/pause, open an app (click again to hide it), open a link in a chosen browser, open a file or folder, press a key combination, or run a Shortcut |

The middle of the trackpad behaves exactly as before. Gestures need a real click: resting fingers, scrolling and tap-to-click never trigger anything.

## Requirements

- macOS 14 Sonoma or later
- A Force Touch trackpad: any MacBook from the last decade, or a Magic Trackpad
- Xcode 16 or later to build

## Build and install

```sh
brew install xcodegen         # only needed if you add or remove source files
scripts/install.sh            # Release build → /Applications/Ledge.app, then opens it
```

Or open `Ledge.xcodeproj` and run the `Ledge` scheme.

On first launch, the welcome guide asks for **Accessibility** (System Settings › Privacy & Security › Accessibility). Ledge does nothing until that switch is on.

### Signing

Out of the box the app is signed ad hoc, so anyone can build it. The catch is that macOS treats every rebuild as a new app and asks for Accessibility again. To avoid that, sign with your own Apple Development certificate:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then put your team ID in it
```

`Config/Local.xcconfig` is git-ignored.

## How it works

```
MultitouchSupport ──frames──▶ TouchEngine ──▶ GestureEngine ◀── EventInterceptor ◀── CGEventTap (left mouse)
  (raw fingers, mm)                              │
                                                 ├─ SystemKeys      NX_KEYTYPE_* key events → volume / brightness + OSD
                                                 ├─ Haptics         MTActuator tick on the trackpad being touched
                                                 ├─ MediaController read position, seek (MediaRemote or AppleScript)
                                                 ├─ SeekHUD         "release to jump" preview panel
                                                 └─ CornerClicks    multi-click counting → CornerActionRunner
```

- **TouchEngine** reads every finger on every trackpad through the private `MultitouchSupport` framework. That includes the surface size in millimetres, so a slide feels the same on a Magic Trackpad as on a MacBook. With two trackpads, the one you touched last is in charge. Devices are picked up again after sleep and when a trackpad connects.
- **EventInterceptor** runs an active `CGEventTap` on its own thread. When a physical click lands while exactly one finger is inside an edge strip, the click is held back and the pointer is frozen in place.
- **GestureEngine** turns the finger's travel into steps (3.4 mm each by default). The steps work like a ratchet, so a finger resting on a boundary can't flicker the level. A click that never slides is replayed to macOS. A finger that leaves the strip before the first step was a drag all along, so the drag goes through. Palms and multi-finger clicks are ignored.
- **Fine control**: hold ⇧⌥ while sliding for quarter steps, the same as the keyboard.

The default geometry follows MacEdge's own demo: 10% edge strips, 20% × 17% corners, and a 2.5% dead zone before seeking starts.

## Media timeline

On macOS 14 – 15.3, Ledge reads the system-wide Now Playing info (MediaRemote), so the timeline works with anything that reports a playback position.

Since **macOS 15.4**, MediaRemote only answers processes with an Apple entitlement. On those systems Ledge drives players through their public scripting interfaces instead:

- Music, Spotify, QuickTime Player and VLC
- `<video>` and `<audio>` in the front tab of Safari, Chrome, Arc, Brave, Edge or Vivaldi. These browsers need **Allow JavaScript from Apple Events** turned on (Safari: Develop menu; Chromium: View › Developer).

macOS asks once per player for Automation permission. Firefox-based browsers can't be scripted this way, so on 15.4+ their videos can't be scrubbed. When nothing scrubbable is playing, a drag along the bottom edge is passed to macOS as a normal drag.

## Settings

- **General**: on/off, launch at login, hide the menu bar icon (open the app again to get back to settings), haptic strength, and a live view of your trackpad and its zones.
- **Gestures**: each edge on or off, swap sides, edge width, distance per step, limit the side edges to their lower half or quarter, require a modifier key, and how much time a full-width slide covers.
- **Corners**: up to four actions per corner, one per click count.
- **About › Troubleshooting**: an opt-in log at `~/Library/Logs/Ledge/ledge.log` that records each click and slide. Useful if a gesture doesn't respond.

## Caveats

- Ledge relies on private frameworks (`MultitouchSupport`, `MediaRemote`), so it can't be sandboxed or shipped on the Mac App Store, and a macOS update could break it.
- The haptic waveform IDs (3 / 4 / 6) come from community research on `MTActuatorActuate`. If a strength feels wrong, change `HapticStrength.actuationID`.

## Project layout

```
Ledge/
  App/        AppDelegate, menu bar item, window management
  Core/       Settings, TouchEngine, ZoneMap, EventInterceptor, GestureEngine, AppStatus, DebugLog
  Actions/    SystemKeys, SystemLevels, Haptics, MediaController, CornerActions
  UI/         Settings tabs, welcome guide, live trackpad preview, seek HUD, shortcut recorder
  Bridge/     Headers for the private MultitouchSupport and MediaRemote frameworks
Config/       Signing.xcconfig (+ your git-ignored Local.xcconfig)
scripts/      install.sh, make-icon.swift
project.yml   XcodeGen spec; regenerate the project with `xcodegen generate`
```

## License

MIT. See [LICENSE](LICENSE). Not affiliated with MacEdge.
