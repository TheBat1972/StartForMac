# StartForMac

**English** | [Русский](README.ru.md)

A "Start button" for macOS, inspired by Windows: all your apps sorted into categories, your own categories, search, quick access to websites, and a set of system and disk tools. Opens from its Dock icon, a hotkey or (optionally) a trackpad gesture.

Personal project, built with SwiftUI + AppKit, no third-party dependencies. Universal binary (Apple Silicon + Intel), macOS 12+.

## Features

- **Apps by category.** Categories come from each app's App Store category; create your own and drag apps into them. The target category is highlighted while dragging.
- **Search** across apps, files and folders (via Spotlight, including text inside files and iCloud Drive), plus a calculator, unit conversion and currency conversion right in the search field; resizable and movable window (size and position are remembered, with minimum and maximum limits), `Esc` closes it. Files from the search results can be dragged with the mouse into any app or Finder — a copy is passed, the original stays in place; a “Show in Finder” button appears at the right of the row on hover. The file context menu has “Copy file” (like ⌘C in Finder: ⌘V pastes a copy) and “Copy path”.
- **Custom icons.** Right-click an app → “Change Icon…”: a window opens with a bank of ready-made icons (about 70 glyphs for different cases: web, chat, work, media, games, development, shopping; the color is selectable), and “Choose File…” takes an image from disk (PNG, JPEG, ICNS…). Handy for web apps or just for customizing. The app itself is not modified; “Restore Original Icon” removes the replacement. Images are kept in `~/Library/Application Support/StartMenu/Icons`. The same works for sites in the Websites tab: right-click a site tile → “Change Icon…” (a custom icon fills the whole tile; “Restore Original Icon” brings back the icon taken from the site itself).
- **Uninstaller.** Right-click an app → Delete: finds leftovers (caches, preferences, containers, logs, launch agents…), shows a preview, asks for confirmation, moves items to the Trash. Items that need admin rights are deleted with the administrator password.
- **Tools** (wrench button). Each one opens in its own window, does not get in the way of Start and lives independently; "Close all apps" stays inside Start:
  - *Take a Break* (the top item) expands into five entries: Tetris, Solitaire, Durak, JezzBall and Lode Runner. *Lode Runner* is the classic: collect all the gold, avoid the guards, climb the ladder that appears; Space digs a hole on the side the runner faces (a guard that falls in is out for a while, holes fill back in), 15 levels. JezzBall and Lode Runner keep a top-12 records table next to the field. *JezzBall* is the classic: balls bounce around the field, a click builds a wall that grows in both directions, a ball hitting a growing half destroys it and costs a life, and areas without balls are filled in until 75% of the field is closed; right-click or Space turns the wall. *Solitaire* is classic Klondike: drag cards with the mouse, double-click sends a card to the foundation, `Z` or the button undoes a move, draw 1 or 3 cards, auto-finish once every card is face up, a card cascade after a win and a top-10 records table (“Records” button) a choice of five card backs and five muted table colours (“View” button). *Durak* is the classic Russian card game against the computer for 2, 3 or 4 players, in two variants: throw-in (*podkidnoy*) and transfer (*perevodnoy*); same cards, card backs and table colours as Solitaire (“View” button). Click a card to lead or throw in; to beat, click the card (if it fits only one attack card it is played at once, otherwise pick the target on the table); “Take”, “Discard” / “Enough” and “Transfer” buttons. The computer players count cards (own hand, discard pile, the open trump and the cards others picked up) and play by a heuristic; at the end of the game they sample the unknown cards many times and play each possible move out to the end (determinization, Perfect Information Monte Carlo). Animated card moves (cards fly to the table, to the discard pile and to the player who takes them); the deck is shown as a stack with the trump under it. The game asks your name on first launch (the “Name” button changes it) and addresses you by it; every player name is shown larger and in its own colour everywhere it appears (readable on all table colours). *Tetris* is ported from Python to Swift. Arrows move and rotate, Space drops the piece, `P` pauses, `Esc` restarts; the game pauses when the window loses focus. The top-12 score table is stored in the app settings. Scoring and levels follow the international Tetris Guideline, so results are comparable: 100 / 300 / 500 / 800 × level for 1–4 lines, +1 point per cell of soft drop (↓) and +2 per cell of hard drop (Space), back-to-back Tetrises ×1.5, combo 50 × count × level; the level rises every 10 lines and the fall speed is (0.8 − (L−1)·0.007)^(L−1) seconds per row. T-spins and perfect clears are not counted.
  - *Calculator* (the second item): styled after the old CalcNew. A simple digital display: the number shrinks to fit any number of digits, the chosen operation is shown above it, and the `M1` and `M2` marks show which memory cells are in use. Action keys in the system accent color, memory keys in a light accent tint (`→M1`, `M1→`, `→M2`, `M2→`) and function keys (`xʸ`, `ʸ√x` — the y-th root of x, `π`, `x!`, `eˣ`, `x²`, `x³`, `√`, `1/x`), `См1` and `См2` (same color as the function keys) that clear the memory cells, plus copy and paste of the number. Percent works as in ordinary calculators: `200 + 10 %` gives 220, `50 × 10 %` gives 5, and with no operation `%` divides the number by 100. It also works from the keyboard: digits, `+ − * /`, `Enter`, `Esc` (clear), `Backspace`, `⌘C` / `⌘V`. The “Converter” tab does everything the search field does: a quick-input line on top (“15% of 8400”, “5 miles to km”, “100 usd to rub”), and below it length, mass, volume, temperature, speed, time, data, area and currencies (about twenty; rates are refreshed at most once an hour, offline the last saved ones are used).
  - *File manager* (the third item): two panes in the spirit of Total Commander. Keyboard: arrows, `PgUp`/`PgDn`, `Home`/`End` move the cursor; `Shift`+arrows select a range (starting from an already selected row deselects), `Space`/`Insert` mark, `⌘A`, `Esc` clears; `Enter` opens a folder or launches a file, `Backspace` goes up, `Tab` and `←`/`→` switch panes. Mouse: `Shift`+click range, `⌘`+click one row. `F2` rename (several files: batch rename with `[N] [E] [C] [Y][M][D]` masks, find and replace, case, counter; if the names clash and there is no `[C]`, a number is added automatically), `F3` view, `F4` edit, `F5` copy, `F6` move, `F7` new folder, `F8`/`Delete` to the Trash; every function is also in the row's context menu. Copy and move ask for the destination and offer replace / skip / apply to all on name clashes. Files can be dropped onto a pane from Start search results, Finder and other apps, and dragged out of a pane into any app. Each pane has a search field like Start's (by name and text inside files). Disks and devices are in the menu left of the path; if a disk is ejected while a pane is on it, the pane returns to Downloads. **Android phones and other MTP devices** (the “File transfer” mode) open in a pane directly over USB, without third-party apps: only copy, rename and delete are available there (file view, edit, move and new folder are disabled); files over 4 GB are not supported yet. Debug log: `~/Library/Logs/Pusk-MTP.log`.
  - *Junk cleanup:* app caches, logs, system caches, Trash, Xcode builds and device support files, installers in Downloads, leftovers of removed apps. Every category expands, and you can pick individual items.
  - *Large and old files:* find files by size and age, move selected ones to the Trash.
  - *Maintenance:* free memory, maintenance scripts, flush DNS cache, speed up Mail, reindex Spotlight, repair permissions, thin Time Machine snapshots. Each task runs separately; nothing is preselected.
  - *Disk analyzer* (DaisyDisk style): sunburst chart of used space, fast scanning with low-level calls, drill-down, move to the Trash. The result is remembered; next time only changed folders are rescanned (using the FSEvents history).
  - *Download and Convert* (formerly a separate app, Download and Convert; opens in a large window with four sections): When the tool opens, the yt-dlp version is checked: if it is older than the latest GitHub release, a warning with an “Update yt-dlp” button appears above the download log (the same in the “Components” tab, which also shows the version). At most once every 12 hours; offline, the check is silently skipped. The same for ffmpeg: it is compared with the latest build, and a warning with an “Update ffmpeg” button appears when a newer one exists. Update buttons in the download window and banners appear only when there is something to update; in the “Components” tab the buttons are always there and their label depends on the state: “Download”, “Update” or “Download again”.
    - *Download from YouTube:* paste a link, pick the quality (best, 1080p, 720p, audio mp3) and a folder; yt-dlp does the download. "Cookies from" helps when YouTube asks to confirm you are not a bot; only installed browsers are listed, Safari by default (Start already has Full Disk Access).
    - *Audio Converter:* any audio or video to MP3, M4A, FLAC, WAV, AIFF, OGG or Opus; a bitrate is chosen for lossy formats.
    - *Text & Documents* (the fourth section): TXT, RTF, HTML, DOC, DOCX, ODT, Markdown, PDF, FB2 and EPUB into each other; headings, bold, italic and links are kept where the format allows. Pictures (PNG, JPEG, TIFF, HEIC…) and scanned PDFs become text with the built-in macOS recognition (Vision), offline and without installing anything; Russian is recognized on macOS 13 and newer.
    - *Video Converter:* MP4, MOV, MKV, WebM, AVI or GIF; H.264 / H.265, quality, Full HD limit, sound mode "With sound" / "No sound" / "Sound only" (the output is then an audio file), HDR tone mapping, trimming and cutting out parts.
    - Conversion uses ffmpeg. ffmpeg and yt-dlp are downloaded once, the first time the tool is opened, into `~/Library/Application Support/DownloadAndConvert` (the "Components" section re-downloads or updates them). Files can be dropped onto the window.
  - *External drives:* format flash drives as real FAT32 (default), FAT16, exFAT, Mac OS Extended or APFS with an MBR or GPT partition map, so the drive is readable on any device. The "Speed" tab measures sequential write and read bypassing the system cache, detects the connection (USB 2.0 … USB4) and compares the result with typical devices: read with read, write with write.
- **Colored category icons.** Settings (“Icons”) can switch the sidebar to colored rounded icons, like in Safe; your own categories look like blue Finder folders; right-click your category → “Icon and color” changes its icon and color (colored mode). Colored icons are the default.
- **“Minimize all windows” button** under “New category”: minimizes the windows of all apps; pressing it again does not restore them (the menu bar icon and the hotkey still do).
- **Recent tab** (the first one in the list). The 100 most recent documents you worked with on this Mac in any app, not only the ones opened through Start: the list comes from Spotlight (last-opened date), like “Recents” in Finder. The number (25 / 50 / 100 / 200) is chosen right on the tab and the list is grouped by day: Today, Yesterday, This week, Earlier. Each file shows its icon, folder, how long ago it was opened and its type; a click opens it, a right click or the button on the right reveals it in Finder, and the file can be dragged into another app. Apps and folders are not listed. Full Disk Access is needed for Desktop, Documents and Downloads.
- **Websites tab.** Quick links with icons taken from the sites themselves, organized in folders (drag a site onto a folder). The icon order is chosen with a switch above the tiles: “Manual” (drag an icon onto another one and it is placed before it, or onto the “Add site” tile to put it last), “A–Z”, or “Frequent” (by number of opens); the choice is remembered. IP addresses and local devices work too (plain `http://` is used for them).
- **Minimize All** (built in, formerly a separate app): menu bar button, hotkey (default `⌃⌥M`), restores windows if the screen is empty, minimize by clicking the active app's Dock icon. Needs the Accessibility permission. Start and its tools are minimized too; the Settings switch “Don’t minimize Start and its tools” (off by default) leaves them in place.
- **Hotkey** to show/hide Start (default `⌃⌥P`) and an optional *thumb + three fingers* pinch gesture (off by default; disable the system gesture first).
- **New clean desktop** (Settings → “System”, off by default): a “+” button in the top bar creates a new, completely clean macOS desktop with its own icons (an app window over the Finder icons, files in a “Desktops” folder in your home folder); the main desktop and iCloud are untouched; drag and drop, ⌘C/⌘V/⌘X; the list survives restarts; when a desktop is deleted (also while the app was not running), the app asks: Trash, move to the main desktop, or keep the folder. Needs Accessibility.
- **Task Manager** (Tools): four tabs. “Processes” — groups by app, expandable; columns CPU, Memory, Disk, Network, Energy (selectable); end, suspend, priority. “History” — accumulated CPU, network and disk per app. “Details” — flat list of all processes with PID and user. “Performance” — graph cards: CPU (per core), memory and pressure, disk, network (interface picker), GPU and battery when present. “Users” (with several accounts), “Services” (launchd: start, stop, restart), “Startup” — login items. Right-click: suspend, priority; warning before ending system processes; CPU auto-rules; always-on-top window; menu-bar icon with a CPU graph.
- **Automatic layout switcher** (Settings → “System”, off by default): fixes a word typed in the wrong layout right after the space, including short words (“И вот”, “А кто это?”), hyphenated words and trailing punctuation; site addresses are left alone. The hotkey (default ⌃⌥Space) fixes the last word or the selected text, and repeated presses toggle back and forth. A word you reverted by hand is remembered and no longer auto-fixed (up to 500 words). Apps can be excluded. Typed text is not stored.
- **Own layout key:** Globe/fn or your own shortcut switches the layout; the system language popup can be hidden.
- **Layout flag** (built-in LangFlag): a small on-screen and menu-bar indicator of the current layout with a flag.
- **Dock window previews:** thumbnails of an app’s windows above its Dock icon on hover.
- **⌥Tab window switcher:** thumbnails, search and window buttons.
- **Window snap:** ⌃⌥ + arrows put the active window in a half of the screen, full screen, or minimize it.
- **⌘X in Finder:** cut files; the next ⌘V moves them.
- **Quick launch:** five slots at the bottom of the panel for favourite apps (the fifth is empty by default, with a plus).
- **About:** version 8.0 and copyright in the app menu.
- **Settings:** language (system / Russian / English), theme (system / light / dark), hotkeys, gesture, launch at login, pin to the Dock first (right of Finder).
- **Permissions:** the Permissions tab explains and opens the right System Settings panes: Full Disk Access (protected folders; also removes macOS prompts about other apps’ data), Accessibility (hotkeys, Minimize All, layout switcher), **Screen & System Audio Recording** — only needed for window thumbnails in ⌥Tab and on Dock hover, Input Monitoring (usually not needed; its status is readable only with Full Disk Access, otherwise “Status unavailable”), App Management (app removal) and Files & Folders. Every item has an “Open Settings” button.

## Privacy and security

- No telemetry, no accounts. The app only contacts the websites you add, to download their icons, an exchange-rate service (open.er-api.com, with cbr-xml-daily.ru as a fallback) when you ask for a currency conversion, and — while you use Download and Convert — ffmpeg.martin-riedl.de and GitHub (downloading ffmpeg and yt-dlp) plus the site whose link you paste.
- The administrator password is typed into an in-app field, passed to `sudo` through stdin, kept in memory for 5 minutes and never written to disk.
- Settings live in `~/Library/Application Support/StartMenu/config.json`.

## Build

Requires Xcode or the Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

The result is `StartForMac.app` (and `StartForMac.zip` when signed with Developer ID). Drag the app to the Dock.

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
| `Sources/WindowSnap.swift` | window control with ⌃⌥ + arrows (halves, fill, minimize) |
| `Sources/FinderCut.swift` | ⌘X in Finder as “cut” (event tap) |
| `Sources/WindowSwitcher.swift` | ⌥Tab window switcher with thumbnails, search and window buttons |
| `Sources/DockPreview.swift` | window previews when hovering a Dock icon |
| `Sources/LayoutSwitcher.swift` | automatic keyboard layout switcher |
| `Sources/LayoutKey.swift` | own layout key (Globe/fn), hiding the system language popup |
| `Sources/TaskManager.swift` | Task Manager: processes, details, performance (disk, network, GPU, battery) |
| `Sources/TaskManagerExtra.swift` | Task Manager: process guard, auto-rules, menu-bar icon, history, users, services |
| `Sources/StartupItems.swift` | Task Manager: startup items |
| `Sources/LayoutFlag.swift` | floating layout flag (built-in LangFlag) |
| `Sources/Clipboard.swift` | smart clipboard history (⇧⌘V, pinning, in-memory, skips passwords) |
| `Sources/CleanDesktop.swift` | new clean desktop (“+” button), incl. time-of-day dynamic wallpapers |
| `Sources/UnRar.swift` | archive extraction (RAR/RAR5, 7z, ZIP, TAR…; passwords, multi-volume) via 7-Zip |
| `Sources/Duplicates.swift` | duplicates and similar photos (SHA-256, perceptual hash) |
| `Sources/Minimize.swift` | Minimize All, hotkeys, login item, Dock pinning |
| `Sources/Gesture.swift` | pinch gesture (private MultitouchSupport framework, loaded dynamically) |
| `Sources/IconPicker.swift` | the icon picker: bank of ready-made icons and an image from disk |
| `Sources/Calculator.swift` | the calculator (display, keys, keyboard) and the unit and currency converter |
| `Sources/Rest.swift` | “Take a Break”: Tetris and the score table |
| `Sources/Solitaire.swift` | “Take a Break”: Klondike Solitaire |
| `Sources/LodeRunner.swift` | “Take a Break”: Lode Runner (15 levels, guard pathfinding, holes, window) |
| `Sources/GameRecords.swift` | records table and name entry for JezzBall and Lode Runner |
| `Sources/JezzBall.swift` | “Take a Break”: JezzBall (field, balls, growing walls, region capture, window) |
| `Sources/Durak.swift` | “Take a Break”: Durak (rules engine, computer player with card counting and PIMC, window) |
| `Cards/` | card images (the author's own deck: 52 faces + back) and the move sound for Solitaire and Durak; `build.sh` copies the folder into `Resources` |
| `Sources/Localization.swift` | Russian / English strings |
| `Sources/DCWindow.swift` | the Download and Convert window: sections, components, quit while busy |
| `Sources/DCDownloader.swift` | download from YouTube (yt-dlp), browser choice for cookies |
| `Sources/DCAudio.swift`, `Sources/DCVideo.swift`, `Sources/DCVideoUI.swift` | audio and video converters, trimming |
| `Sources/DCText.swift` | the “Text & Documents” section: text format conversion and text recognition |
| `Sources/TwoPane.swift` | the “File manager” tool: two panes, copy/move/delete, batch rename, drag & drop |
| `Sources/MTP.swift` | Android phones over USB (MTP) for the file manager: device search, protocol, copy/rename/delete |
| `Sources/DCTools.swift`, `Sources/DCComponents.swift`, `Sources/DCStrings.swift` | ffmpeg and yt-dlp, shared UI pieces, the tool's strings |
| `Tools/make_icon.swift` | draws the app icon at build time |
| `build.sh` | build, sign, notarize |
