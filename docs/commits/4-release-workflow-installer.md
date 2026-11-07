# 4th commit: github release workflow, one-line curl installer, build script renamed, readme install and releasing docs

## Context
Ledge is free and open source with no paid Apple Developer ID. Without one, macOS blocks an ad hoc signed app downloaded through a browser. This commit gives people a way to install a prebuilt Ledge without building it: a tag-triggered GitHub Actions build plus a one-line Terminal installer.

## Changes
- [.github/workflows/release.yml](../../.github/workflows/release.yml): on a `v*` tag, builds a universal Release on `macos-15`, using ad hoc signing from `Config/Signing.xcconfig`. It verifies the signature, zips the app with a SHA-256 file, and publishes a GitHub Release via `gh`. Running it by hand builds and uploads an artifact without publishing.
- [install.sh](../../install.sh): downloads the latest release with curl, checks the checksum and the code signature, and replaces any existing copy. It quits only the copy running from that path, clears the stale Accessibility entry on updates, then opens the app. `LEDGE_INSTALL_DIR` and `LEDGE_NO_OPEN` cover other install locations and scripted use.
- `scripts/install.sh` is renamed to [scripts/build-and-install.sh](../../scripts/build-and-install.sh), so it isn't confused with the root installer.
- [README.md](../../README.md): new Install section with the one-liner and the reason it's a Terminal command. "Build and install" becomes "Build from source", and there's a Releasing section. The project layout gains the new files.

## Why
Developer ID and notarization cost $99/year, which the project doesn't want. Files fetched with curl aren't quarantined, so Gatekeeper doesn't block them. That's the same approach MacEdge's own installer uses, and the script is short enough to read before piping. The checksum and `codesign --verify` steps catch a corrupt or tampered download. Each ad hoc build has a new signature, so on update the old Accessibility entry would silently stop matching. Resetting it lets the welcome guide ask again cleanly.

## Files
| File | Change |
|---|---|
| .github/workflows/release.yml | new release workflow |
| install.sh | new curl installer |
| scripts/build-and-install.sh | renamed from scripts/install.sh |
| README.md | install, build from source, releasing |

## Verification
- `bash -n install.sh` passes, and the workflow YAML parses.
- After pushing: run the workflow by hand and confirm the build and artifact. Then tag `v1.0.0`, confirm the release has `Ledge.zip` and `Ledge.zip.sha256`, and run `install.sh` with `LEDGE_INSTALL_DIR` set to a temp folder and `LEDGE_NO_OPEN=1` to check download, checksum, unpacking and the missing quarantine flag.

## Rollback
`git revert` removes the workflow and the installer and restores the old script name. Delete any published GitHub Releases and tags by hand.
