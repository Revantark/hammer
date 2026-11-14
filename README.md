# Hammer

A minimal macOS app launcher and clipboard manager. Swift + AppKit, no dependencies.

- **⌘Space** — launcher: type, ↑/↓, Enter to open (or bring forward) an app. With an empty search, the 5 apps you opened last sit in a **Recent** section above all apps A–Z. Typing fuzzy-searches, ranked by how often and how recently you use each app.
- **Calculator** in the launcher: type `8/32`, `10 % 3` or `8(5+3*2+(4*2 + 5 - 10)/2)` and the result shows on top; Enter copies it. `+ - * / ^`, `×` `÷`, parentheses (left open ones close themselves), `2(3)`-style multiplication, `%` (remainder between two numbers, percent otherwise: `200*10%` = 20), `sqrt()`/`√`, `pi`, `e`.
- **Commands** in the launcher: type `/` to list them, keep typing to filter, Enter or Tab picks one, then its argument list appears.
  - `/kill <app>` force-quits a running app (unsaved work is lost). `/quit <app>` asks it to quit, so it can still ask to save.
  - `/uninstall <app>` lists the app and the files it left in `~/Library` (only folders and files named exactly after its bundle ID or name), each with its size. Space unticks one, Enter moves the ticked ones to the **Trash** (nothing is deleted outright; Finder's Put Back works), Esc goes back. A running app is asked to quit first. Root-owned apps (App Store, installers) go through Finder, which asks for your password. Apps installed with Homebrew show `brew uninstall --cask --zap <name>` instead; Enter copies it. macOS's own apps and Hammer aren't listed.
- **⌥X** — clipboard: the latest 25 copies (text and images), newest first. Typing also searches everything you copied in the last 4 days (up to 1,000 older entries, newest 200 matches shown). ↑/↓ or Tab/⇧Tab to move, Enter pastes into the app you were in and moves the entry back to the top.
- Both shortcuts can be changed in Settings (**⌘,** while the panel is open).

## Build and install

```bash
scripts/make-signing-identity.sh   # once: creates a local code-signing identity (macOS may ask for your login password once)
scripts/build-app.sh               # builds and signs build/Hammer.app
cp -R build/Hammer.app /Applications/
open /Applications/Hammer.app
```

Signing with a stable identity means macOS remembers Hammer's Accessibility permission across rebuilds.

## First run

1. **Free up the shortcuts.** macOS sends a shortcut to only one app when two apps claim it, and it doesn't report a conflict.
   - **Raycast:** quit it, or clear its hotkey (Raycast Settings → General → Raycast Hotkey) and its clipboard-history hotkey if it's ⌥X.
   - **Spotlight:** System Settings → Keyboard → Keyboard Shortcuts → Spotlight → turn off "Show Spotlight search". Hammer tells you once if Spotlight still owns ⌘Space.
2. **Allow auto-paste.** The first time you press Enter in the clipboard, macOS asks to give Hammer **Accessibility** access (System Settings → Privacy & Security → Accessibility). Until you allow it, Enter copies the entry and you press ⌘V yourself.
3. **Launch at login** is on by default (toggle it in Settings).

Hammer has no Dock icon. The menu bar icon is **off by default** because it costs about 3 MB of memory; turn it on in Settings.

## Data

`~/Library/Application Support/Hammer/` holds `settings.json`, `frecency.json` (launcher usage) and `clipboard/` (`index.json` for the latest 25, `archive.tsv` for the 4 days before them, plus one file per entry). Everything you copy is recorded, including copies from password managers. Settings → "Clear Clipboard History…" deletes it all.

## Development

```bash
swift test                 # unit tests (Swift Testing)
scripts/test-repeat.sh 5   # whole suite 5× to catch flaky tests
scripts/check-latency.sh   # keystroke→results p99 < 16 ms, each ↓ through the clipboard p95 < 16 ms, hotkey→visible p95 < 50 ms
scripts/check-memory.sh    # Activity Monitor "Memory": fresh idle ≤ 10 MB, open ≤ 30 MB (incl. searching a full 1,000-entry archive), idle after use ≤ 30 MB
```

The check scripts run Hammer in a test mode (`HAMMER_DEBUG_SIGNALS=1`): no global hotkeys, no login item, a temp data folder and a private pasteboard. It never touches your real shortcuts or clipboard.

Layout: `Sources/HammerCore` (all logic, no UI, fully unit-tested with fakes), `Sources/HammerMac` (AppKit/Carbon adapters and the Frost UI), `Sources/Hammer` (app entry point), `Sources/HammerBench` (search benchmark).

Measured on the owner's Mac (2026-11-13): fresh idle 7.9 MB, launcher open 18 MB, clipboard open with a 2560×1600 screenshot 24–30 MB, idle after use ~18–26 MB (heap memory AppKit/ImageIO don't hand back). Search < 1 ms; launcher opens in ~28 ms, clipboard with 10 screenshots in ~29 ms (the first open after launch ~120 ms).
