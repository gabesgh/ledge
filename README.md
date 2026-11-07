# Ledge

Ledge turns the edges of your Mac trackpad into controls for volume, brightness, media playback and shortcuts. It's an open-source rebuild of [MacEdge](https://macedge.site/), written from scratch in Swift, and it lives in the menu bar.

Press an edge until the trackpad clicks, then slide.

| Where | What it does |
| --- | --- |
| Right edge | System volume. Same 16 steps as the volume keys, same macOS indicator. |
| Left edge | Brightness of the built-in display, in the same steps. |
| Bottom edge | Scrubs whatever is playing. Slide sideways and let go to jump. |
| Top corners | One to four clicks each. Mute, play or pause, open an app and hide it on the next click, open a link in a browser you pick, open a file or folder, press a key combination, or run a Shortcut. |

The rest of the trackpad works as before. A gesture only starts on a physical click, so resting fingers, scrolling and tap to click never set one off.

## Requirements

- macOS 14 Sonoma or later
- An Apple trackpad, built in or Magic Trackpad. The haptic ticks need a Force Touch model.
- Xcode 16 or later. I build with Xcode 26.

## Build and install

```sh
brew install xcodegen         # only needed after adding or removing source files
scripts/install.sh            # builds Release, copies it to /Applications and opens it
```

You can also open `Ledge.xcodeproj` and run the `Ledge` scheme.

The first launch opens a welcome guide that asks for Accessibility access, under System Settings › Privacy & Security › Accessibility. Ledge can't do anything until you turn that on.

### Signing

The project signs the app ad hoc, so it builds on any Mac with no setup. The downside is that macOS sees every rebuild as a new app and asks for Accessibility again, which gets old after the second rebuild. If you have an Apple Development certificate, sign with it instead:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Then put your team ID in `Config/Local.xcconfig`. Git ignores that file.

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

`TouchEngine` reads every finger on every trackpad through Apple's private `MultitouchSupport` framework. The framework reports each trackpad's size in millimetres, so a slide covers the same distance on a MacBook as on a Magic Trackpad. With two trackpads, the one you touched last is in charge. Ledge picks the devices up again after sleep and when a trackpad connects.

`EventInterceptor` runs a `CGEventTap` on its own thread. When a physical click lands and exactly one finger sits inside an edge strip, Ledge holds the click back and freezes the pointer.

`GestureEngine` turns finger travel into steps, 3.4 mm per step by default. Turning back takes 60% of a step, which stops a finger resting on a step boundary from flickering the level up and down. If the finger never slides, Ledge replays the click to macOS. If it leaves the strip before the first step, it was a drag all along, and the drag goes through. Palms and multi-finger clicks don't count.

Hold ⇧⌥ while sliding for quarter steps, the same as on the keyboard.

The default sizes come from MacEdge's own demo. Edge strips take 10% of the trackpad, corners are 20% wide and 17% tall, and seeking waits for 2.5% of sideways travel before it starts.

## Media timeline

On macOS 14 through 15.3, Ledge reads the system-wide Now Playing info from MediaRemote, so anything that reports a playback position works.

macOS 15.4 locked MediaRemote to apps with an Apple entitlement. On newer systems Ledge talks to players through AppleScript instead, which covers:

- Music, Spotify, QuickTime Player and VLC
- `<video>` and `<audio>` in the front tab of Safari, Chrome, Arc, Brave, Edge or Vivaldi

The browsers need Allow JavaScript from Apple Events turned on. Safari keeps it in the Develop menu, Chromium browsers under View › Developer. macOS asks once per player for Automation permission.

Firefox and the browsers built on it don't offer this kind of scripting, so on 15.4 and later you can't scrub their videos. That's the biggest gap right now. When nothing scrubbable is playing, a drag along the bottom edge goes to macOS as a normal drag.

## Settings

General has the on/off switch, launch at login, haptic strength, a live view of your trackpad and its zones, and an option to hide the menu bar icon. With the icon hidden, open Ledge again from Applications to get back to settings.

Gestures turns each edge on or off, swaps sides, sets the edge width and the distance per step, limits the side edges to their lower half or quarter, requires a modifier key, and sets how much time a full-width slide covers.

Corners takes up to four actions per corner, one for each click count.

About has an opt-in diagnostic log. It writes each click and slide to `~/Library/Logs/Ledge/ledge.log`, the first place to look when a gesture doesn't respond.

## Caveats

Ledge depends on two private frameworks, `MultitouchSupport` and `MediaRemote`. That rules out the sandbox and the Mac App Store, and any macOS update could break it.

The haptic waveform IDs 3, 4 and 6 come from community reverse engineering of `MTActuatorActuate`, not from Apple. If a strength feels off, change `HapticStrength.actuationID`.

## Project layout

```
Ledge/
  App/        AppDelegate, menu bar item, window management
  Core/       Settings, TouchEngine, ZoneMap, EventInterceptor, GestureEngine, AppStatus, DebugLog
  Actions/    SystemKeys, SystemLevels, Haptics, MediaController, CornerActions
  UI/         Settings tabs, welcome guide, live trackpad preview, seek HUD, shortcut recorder
  Bridge/     Headers for the private MultitouchSupport and MediaRemote frameworks
Config/       Signing.xcconfig, plus your git-ignored Local.xcconfig
scripts/      install.sh, make-icon.swift
project.yml   XcodeGen spec. Regenerate the project with `xcodegen generate`.
```

## License

MIT, see [LICENSE](LICENSE). Ledge has no connection to MacEdge or its developer.
