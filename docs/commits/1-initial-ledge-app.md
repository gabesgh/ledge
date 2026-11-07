# 1st commit: ledge menu bar app, edge volume and brightness, media timeline scrubbing, corner shortcuts, settings and welcome guide, live trackpad preview, xcconfig signing, readme and mit license

## Context
Ledge is an open-source take on MacEdge (macedge.site). It turns the edges of a Mac trackpad into controls: physically click an edge strip, then slide. The right edge sets volume, the left sets brightness, the bottom scrubs whatever is playing, and the top corners run 1–4-click shortcuts. This commit is the whole first version, cleaned up for a public repo.

## Changes
- **Touch input**: [TouchEngine.swift](../../Ledge/Core/TouchEngine.swift) reads raw fingers from every trackpad via private `MultitouchSupport` (headers in [Bridge/](../../Ledge/Bridge/)). It re-enumerates on wake and when a trackpad connects or disconnects.
- **Click interception**: [EventInterceptor.swift](../../Ledge/Core/EventInterceptor.swift) runs an active `CGEventTap` on a dedicated thread.
- **Gesture state machine**: [GestureEngine.swift](../../Ledge/Core/GestureEngine.swift) turns slides into ratcheted steps and freezes the pointer. It replays clicks that don't slide and passes through drags that leave the strip. [Zones.swift](../../Ledge/Core/Zones.swift) holds the geometry.
- **Actions**: [SystemKeys.swift](../../Ledge/Actions/SystemKeys.swift) (NX key events, giving the system OSD and native steps), [Haptics.swift](../../Ledge/Actions/Haptics.swift) (`MTActuator` ticks), [SystemLevels.swift](../../Ledge/Actions/SystemLevels.swift) (no tick at the ends of the range), [CornerActions.swift](../../Ledge/Actions/CornerActions.swift) (multi-click counting and corner actions).
- **Media**: [MediaController.swift](../../Ledge/Actions/MediaController.swift) uses MediaRemote in-process on macOS < 15.4 and AppleScript for Music, Spotify, QuickTime, VLC and browser `<video>` everywhere. [SeekHUD.swift](../../Ledge/UI/SeekHUD.swift) shows the "release to jump" preview.
- **UI**: settings tabs, welcome guide, live trackpad preview, shortcut recorder, menu bar item.
- **Diagnostics**: an opt-in log at `~/Library/Logs/Ledge/ledge.log` ([DebugLog.swift](../../Ledge/Core/DebugLog.swift)).
- **Build**: XcodeGen spec, with signing in [Config/Signing.xcconfig](../../Config/Signing.xcconfig) (ad hoc by default, a git-ignored `Local.xcconfig` for your own certificate), plus an install script and an icon generator.

## Why
- **Pointer freeze runs off the tap thread.** Calling `CGAssociateMouseAndMouseCursorPosition` inside the tap callback risks stalling the tap while the window server waits on it, so cursor calls run on their own serial queue.
- **No perl helper for MediaRemote.** macOS 15.4+ refuses MediaRemote to unentitled apps. A perl-hosted helper gets around that check, but it was left out because it deliberately bypasses an Apple protection. AppleScript covers the common players instead.
- **Ad-hoc default signing.** Anyone can clone and build, and no team ID lives in the repo.
- **Ratchet steps.** A reversal needs 60% of a step, so a finger resting on a boundary can't flicker the level.

## Files
| File | Change |
|---|---|
| Ledge/Core/* | touch input, zones, event tap, gesture engine, settings, status, log |
| Ledge/Actions/* | keys, haptics, levels, media control, corner actions |
| Ledge/UI/* | settings, onboarding, preview, seek HUD, shortcut recorder |
| Ledge/App/* | app delegate, menu bar item, windows |
| Ledge/Bridge/* | private framework headers |
| Ledge/Resources/Assets.xcassets | generated app icon |
| Config/* | signing xcconfig and local example |
| project.yml, Ledge.xcodeproj | XcodeGen spec and generated project |
| scripts/* | install script, icon generator |
| README.md, LICENSE | docs, MIT license |

## Verification
- Debug and Release builds succeed with no warnings in Ledge sources.
- Tested on a MacBook with macOS 26.7.1, built-in trackpad plus a Magic Trackpad. With the diagnostic log on, a right-edge slide gave volume in exact 1/16 steps (mute at zero, unmute going up). A left-edge slide took brightness from 82% to 1% and back. A top-left click muted. A bottom-edge drag with nothing scrubbable playing passed through as a normal drag.
- The player AppleScripts compile against the installed Music, Spotify, QuickTime, Safari and Chrome dictionaries.

## Rollback
Initial commit; nothing to revert to. Remove `/Applications/Ledge.app` and its Accessibility entry to uninstall.
