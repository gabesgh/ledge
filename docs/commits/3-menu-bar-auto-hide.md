# 3rd commit: auto-hide menu bar icon option, menu bar icon mode picker, legacy setting migration

## Context
Some people don't want a permanent menu bar icon for an app they never look at. The status menu now has an "Auto-hide Menu Bar Icon" toggle. With it on, the icon stays while Ledge is in front or its menu is open, and disappears 5 seconds after you leave. Opening Ledge again from Spotlight or Applications brings it back.

## Changes
- [Settings.swift](../../Ledge/Core/Settings.swift): new `MenuBarIconMode` (`always`, `autoHide`, `hidden`) replaces the `showMenuBarIcon` bool. `autoHideExplained` records that the one-time explanation was shown. `Prefs.load` maps an old `showMenuBarIcon` value onto the new mode.
- [StatusItemController.swift](../../Ledge/App/StatusItemController.swift): adds the auto-hide menu item and `apply(_:)`. `updateVisibility()` watches app activation and menu open/close, and schedules the hide after `autoHideDelay` (5 s). On first enable, it shows an alert explaining how to get the icon back. An `autosaveName` keeps the icon's position when it reappears.
- [AppDelegate.swift](../../Ledge/App/AppDelegate.swift): feeds `menuBarIcon` changes to the status item.
- [SettingsView.swift](../../Ledge/UI/SettingsView.swift): General has a "Menu bar icon" picker in place of the on/off toggle.
- [README.md](../../README.md): the Settings section describes the three modes.

## Why
"Inactivity" means Ledge isn't the active app and its menu is closed. Ledge does its work without ever being frontmost, so gestures don't count as activity. Counting them would make the icon blink in and out while you adjust the volume. The one-time alert exists because an icon that silently vanishes, with no obvious way back, looks like a crash.

## Files
| File | Change |
|---|---|
| Ledge/Core/Settings.swift | `MenuBarIconMode`, migration from the old bool |
| Ledge/App/StatusItemController.swift | auto-hide toggle, visibility timer, first-run alert |
| Ledge/App/AppDelegate.swift | wires the mode to the status item |
| Ledge/UI/SettingsView.swift | picker replaces toggle |
| README.md | settings description |

## Verification
- Debug and Release builds succeed. Installed to /Applications.
- Manual check: turn on Auto-hide in the menu, read the alert, switch to another app. The icon disappears after about 5 s. Open Ledge from Spotlight: Settings opens and the icon returns. Leave again, and it hides 5 s later.

## Rollback
`git revert` restores the always/hidden toggle. A stored `menuBarIcon` value is then ignored, and the icon falls back to always shown.
