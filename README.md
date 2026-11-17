# Start (Пуск)

**English** | [Русский](README.ru.md)

A "Start button" for macOS, inspired by Windows: all your apps sorted into categories, your own categories, search, quick access to websites, and a set of system and disk tools. Opens from its Dock icon, a hotkey or (optionally) a trackpad gesture.

Personal project, built with SwiftUI + AppKit, no third-party dependencies. Universal binary (Apple Silicon + Intel), macOS 12+.

## Features

- **Apps by category.** Categories come from each app's App Store category; create your own and drag apps into them. The target category is highlighted while dragging.
- **Search**, resizable and movable window (size and position are remembered, with minimum and maximum limits), `Esc` closes it.
- **Uninstaller.** Right-click an app → Delete: finds leftovers (caches, preferences, containers, logs, launch agents…), shows a preview, asks for confirmation, moves items to the Trash. Items that need admin rights are deleted with the administrator password.
- **Tools** (wrench button). Each one opens in its own window, does not get in the way of Start and lives independently; "Close all apps" stays inside Start:
  - *Junk cleanup:* app caches, logs, system caches, Trash, Xcode builds and device support files, installers in Downloads, leftovers of removed apps. Every category expands, and you can pick individual items.
  - *Large and old files:* find files by size and age, move selected ones to the Trash.
  - *Maintenance:* free memory, maintenance scripts, flush DNS cache, speed up Mail, reindex Spotlight, repair permissions, thin Time Machine snapshots. Each task runs separately; nothing is preselected.
  - *Disk analyzer* (DaisyDisk style): sunburst chart of used space, fast scanning with low-level calls, drill-down, move to the Trash. The result is remembered; next time only changed folders are rescanned (using the FSEvents history).
  - *External drives:* format flash drives as real FAT32 (default), FAT16, exFAT, Mac OS Extended or APFS with an MBR or GPT partition map, so the drive is readable on any device. The "Speed" tab measures sequential write and read bypassing the system cache, detects the connection (USB 2.0 … USB4) and compares the result with typical devices: read with read, write with write.
- **Websites tab.** Quick links with icons taken from the sites themselves, organized in folders (drag a site onto a folder). IP addresses and local devices work too (plain `http://` is used for them).
- **Minimize All** (built in, formerly a separate app): menu bar button, hotkey (default `⌃⌥M`), restores windows if the screen is empty, minimize by clicking the active app's Dock icon. Needs the Accessibility permission.
- **Hotkey** to show/hide Start (default `⌃⌥P`) and an optional *thumb + three fingers* pinch gesture (off by default; disable the system gesture first).
- **About:** version and copyright in Settings and in the app menu.
- **Settings:** language (system / Russian / English), hotkeys, gesture, launch at login, pin to the Dock first (right of Finder).
- **Permissions:** Full Disk Access (to clean protected folders) and Accessibility (for Minimize All) are explained and requested inside the app.

## Privacy and security

- No telemetry, no accounts. The app only contacts the websites you add, to download their icons.
- The administrator password is typed into an in-app field, passed to `sudo` through stdin, kept in memory for 5 minutes and never written to disk.
- Settings live in `~/Library/Application Support/StartMenu/config.json`.

## Build

Requires Xcode or the Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

The result is `Пуск.app` (and `Пуск.zip` when signed with Developer ID). Drag the app to the Dock.

## Signing and notarization

By default `./build.sh` signs with the Developer ID certificate named in a local file `.sign.local` (not committed; see `.sign.local.example`) and notarizes with the notarytool profile from the same file. Without that file the app is signed ad-hoc, which is fine for your own Mac only.

```bash
# one time: store notarization credentials (app-specific password from appleid.apple.com)
xcrun notarytool store-credentials "my-notary" --apple-id "you@example.com" --team-id "TEAMID" --password "xxxx-xxxx-xxxx-xxxx"

# find your certificate
security find-identity -v -p codesigning

# build, sign, notarize
SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="my-notary" ./build.sh

# quick build: signed, but not notarized
NOTARY_PROFILE= ./build.sh
```
If several certificates share the same name, pass the SHA-1 hash instead of the name.

See [CHANGELOG.md](CHANGELOG.md) for the list of changes.

## Files

| File | Purpose |
|---|---|
| `Sources/main.swift` | UI, app list, uninstaller, tool windows (cleanup, disk analyzer, external drives), websites, settings |
| `Sources/Minimize.swift` | Minimize All, hotkeys, login item, Dock pinning |
| `Sources/Gesture.swift` | pinch gesture (private MultitouchSupport framework, loaded dynamically) |
| `Sources/Localization.swift` | Russian / English strings |
| `Tools/make_icon.swift` | draws the app icon at build time |
| `build.sh` | build, sign, notarize |
