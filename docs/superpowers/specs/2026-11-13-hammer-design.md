# Hammer — Design

Date: 2026-11-13
Status: Draft, awaiting approval

## 1. Intent

Hammer is a minimal, personal macOS launcher plus clipboard manager. The owner uses Raycast daily but only needs two of its features, the app launcher and clipboard history, and wants everything else gone. Hammer should feel like those two Raycast features and nothing more: instant on keypress, clean, and so light it's invisible in Activity Monitor.

Success means the owner can replace Raycast for their daily use of Cmd+Space and clipboard history, without noticing any lag, and Hammer's memory stays inside the budgets below.

## 2. Goals

1. **App launcher.** Press Cmd+Space, type, press Enter, and the app launches.
2. **Clipboard manager.** Press Opt+X to see the latest 25 copies (text and images). Enter pastes the selected one into the app you were in.
3. **Raycast-like look ("Frost")** that is neat and minimal (see §6).
4. **Ultra-fast.** Hotkey to visible panel under 50 ms, and each keystroke to updated results under 16 ms (one frame).
5. **Tiny memory.** Measured as Activity Monitor's "Memory" column (`phys_footprint`):
   - **≤ 10 MB idle** (panel hidden) on a fresh start
   - **≤ 30 MB with the panel open**, including when an image preview is shown
   - *Owner decision 2026-11-13, after measurement:* once the panel has been used, idle settles higher (~18 MB, ~26 MB after an image preview) because AppKit/ImageIO heap fragmentation can't be handed back. Accepted (≤ 30 MB) instead of self-restarting the app.
6. **Hotkeys you can change** from a Settings window.
7. **Thorough, non-flaky tests** for every function (§9).
8. **Ready to grow.** The launcher is built so files, calculator and unit conversions can be added later as new result sources, without changing the core (§5.3).

## 3. Non-goals (this version)

- Files, calculator, conversions, web search, System Settings panes, snippets, extensions, AI, window management. (Only apps ship now, but the architecture must allow these later.)
- Copied **files** from Finder in clipboard history. Only text and images are kept.
- Windows/Linux. **macOS only.**
- App Store distribution, notarization, auto-update.
- Sync across devices.

## 4. Anti-goals (failure even if it "works")

- Noticeable lag on hotkey or typing.
- Memory beyond the budgets. That's why GPUI and SwiftUI are ruled out (§7).
- Visual clutter: extra panels, onboarding screens, badges, upsells, Raycast-style feature sprawl.
- Flaky tests.

## 5. Behavior

### 5.1 One panel, two modes

Hammer shows a single floating panel with two modes: **Launcher** and **Clipboard**.

- Cmd+Space opens it in Launcher mode, and Opt+X opens it in Clipboard mode. Both hotkeys can be changed.
- If the panel is open, pressing the other mode's hotkey switches mode. Pressing the same mode's hotkey hides the panel.
- The panel appears centered horizontally on the screen the mouse is on, in the upper third.
- Each time it opens, the search box is empty and focused, and the first row is selected.
- **Esc** or clicking outside hides it. **↑/↓** move the selection. **Enter** acts on the selected row.
- **Cmd+,** while the panel is open opens Settings.
- The panel must not steal "frontmost app" status in a way that breaks pasting back into the previous app. A non-activating `NSPanel` is expected; the builder should verify this with auto-paste.

### 5.2 Launcher

- **Sources of apps:** `/Applications`, `/System/Applications` (including `Utilities`), `~/Applications`, recursively for `.app` bundles (don't descend into `.app` bundles). Display name comes from the bundle's localized name.
- **Live refresh:** the app list updates automatically when apps are installed or removed (FSEvents on those folders). No manual rescan.
- **Icons:** real app icons from macOS (`NSWorkspace.icon(forFile:)`), rendered at row size. Load them lazily for visible rows only, and keep a small bounded cache.
- **Fuzzy matching:** prefix, word-initial (`vsc` → Visual Studio Code), substring, and in-order subsequence (`sfri` → Safari). Case-insensitive and diacritic-insensitive. Small-typo tolerance is nice to have, but only if it doesn't hurt ranking quality.
- **Ranking:** match quality first, then usage ("frecency": how often plus how recently the owner launched it). Usage history is stored locally.
- **Empty query** shows the most-used apps, so Cmd+Space → Enter reopens your usual app.
- **Enter** launches the app, or brings it to the front if it's already running, then hides the panel.
- Results show a section label "Applications" and a right-aligned "Application" type label, like the mockup.

### 5.3 Extensibility (designed now, built later)

Launcher results come from **result sources**. Each source takes the query and returns scored results, each with an action. Apps is the only source now. Files, calculator and conversions will be added later as new sources, feeding the same list, ranking, and keyboard handling. Adding a source must not require changing the panel, ranking merge, or key handling.

### 5.4 Clipboard manager

- **Captures** every copy of text or images, from any app. **Everything is recorded, including password-manager copies.** This is the owner's explicit choice. Ignore the `org.nspasteboard.ConcealedType` / `TransientType` markers.
- **Skips** copied Finder files (pasteboard holds file URLs). When a file URL is present, skip the whole copy, including the icon image Finder also puts on the pasteboard.
- **Keeps the latest 25.** When the 26th arrives, the oldest is deleted (including its image file).
- **Dedupe:** copying something that's already in history moves it to the top instead of adding a duplicate.
- **Persists** across quit and reboot, under `~/Library/Application Support/Hammer/`.
- **Search box** filters the 25 entries (text content; images match on "image" and their source app name).
- **Enter pastes:** writes the entry back to the pasteboard, moves it to the top, hides the panel, returns focus to the previous app, and sends Cmd+V. Hammer's own write must not create a duplicate entry.
- **Fidelity:** pasting should give back what was copied. Text keeps its rich formatting if the original copy had it, and images paste as images.
- **Detection:** macOS has no pasteboard-changed notification, so poll `NSPasteboard.changeCount` on a cheap timer. Choose an interval that feels instant without costing idle CPU; a few hundred ms is typical.
- **Layout** (see §6): list on the left grouped by day ("Today", "Yesterday", then dates), newest on top; large preview on the right with details underneath:
  - Image: preview scaled to fit, then source app, pixel dimensions, and copied time.
  - Text: full text (monospace if it looks like code is the builder's call), then source app, character count, and copied time.
- **Memory:** images are stored on disk at original fidelity. Only downscaled thumbnails and the one visible preview, decoded at panel size (ImageIO thumbnailing, never a full-resolution decode), are held in memory.

### 5.5 Settings window

Opened from the menu bar icon or Cmd+, in the panel. It's a plain AppKit window, created on demand and freed when closed. It contains:

- Launcher hotkey and clipboard hotkey. You click a box and press the key combination. Reject combos that are already taken or invalid, and show a short inline message.
- Launch at login (on by default, via `SMAppService`)
- Clear clipboard history (with confirmation)
- Show/hide menu bar icon

Settings persist across restarts.

### 5.6 App presence

- No Dock icon and no Cmd+Tab entry (accessory activation policy).
- A menu bar icon (hammer glyph) with **Settings…** and **Quit Hammer**. **Hidden by default** (owner decision 2026-11-13: the status item costs ~3 MB idle); it can be turned on in Settings. Cmd+, inside the panel always opens Settings.

### 5.7 Permissions and first run

- **Accessibility** permission is needed to send Cmd+V for auto-paste. On first paste attempt without permission, show a one-line prompt that opens the right System Settings pane. Until it's granted, Enter in clipboard mode still copies the entry to the pasteboard (and the owner presses Cmd+V manually).
- Global hotkeys use Carbon `RegisterEventHotKey`, which needs no permission.
- **Cmd+Space conflict:** Spotlight owns Cmd+Space. If registering it fails, show one notice explaining how to turn off Spotlight's shortcut (System Settings → Keyboard → Keyboard Shortcuts → Spotlight). Hammer must not try to take it over silently.

## 6. Visual design: "Frost"

Chosen from three mockups (saved in `.superpowers/brainstorm/…/content/look.html` and `clipboard.html`).

- Frosted dark glass over the desktop (`NSVisualEffectView`, dark material), 14 pt corner radius, a subtle 1 px light border, and a soft shadow.
- Top: search field with a magnifier glyph, ~19 pt text, and a hairline divider below.
- Launcher: section label ("Applications", small semibold, muted), rows ~36 pt tall with a 24 pt app icon, name, right-aligned muted type label, and the selected row on a soft light-translucent rounded background.
- Clipboard: two columns (list ~44% | preview), hairline divider between.
- Footer bar: left shows "Hammer" or "Clipboard · N items"; right shows key hints (`Open ↵`, `Clipboard ⌥X` / `Paste ↵`, `Launcher ⌘Space`) using small rounded key caps.
- Size: launcher ~620 pt wide, clipboard ~760 pt wide (builder may tune).
- Dark appearance only for v1. Following system light mode is not required.
- Font: system font (SF Pro). No custom fonts.
- Animation: none or near-instant. Showing the panel must never wait on an animation.

## 7. Technology (decided)

- **Swift + AppKit.** No SwiftUI, no GPUI, no web views.
- **Why:** a spike on 2026-11-13 measured `phys_footprint`, release builds, on this Mac:

  | Setup | Panel open | Idle (window closed) |
  |---|---|---|
  | GPUI 0.2.2 (Rust; latest, matches Zed main) | 85 MB (93 with screenshot; peak 144) | 34 MB |
  | Native AppKit window, 25 text rows (Swift) | 12 MB | not measured |

  GPUI can't meet the budget. SwiftUI is excluded on the expectation that it adds memory (not measured). The owner chose Swift over Rust + objc2 because the memory is the same and the friction is lower.
- **Single process** for hotkeys, clipboard watcher, launcher and UI.
- **Swift Package Manager** project, producing a `.app` bundle via a build script. Minimum macOS 15. The owner runs macOS 26.
- **Code signing:** sign with a stable local identity (self-signed certificate created once) so the Accessibility permission survives rebuilds.
- **No third-party dependencies** unless there's a strong reason. Prefer system frameworks.

## 8. Structure

Two layers, so logic can be tested without UI or system calls:

- **Core module (pure logic, no AppKit, no system side effects):** fuzzy matcher, ranking and frecency, result-source protocol and merging, clipboard history model (25 cap, dedupe, move-to-top, search), app catalog model, settings model including hotkey validation, and persistence (encoding/decoding to a given directory). Time, file locations, and IDs are injected.
- **App module (AppKit + system glue):** panel and views, Settings window, menu bar item, hotkey registration, pasteboard watcher, paste sender, app launcher, FSEvents watcher, icon loader, login item. Each system touchpoint sits behind a small protocol so the core and the controllers can be tested with fakes.

## 9. Testing (owner requirement: everything tested, nothing flaky)

- **Every function in the core module has unit tests**, including edge cases: empty query, unicode/diacritics, ties in ranking, 25→26 eviction, dedupe of identical text and identical images, corrupt or missing persistence files, invalid hotkeys.
- **Controllers in the app module** (what happens on Enter, on mode switch, on a new copy, on app install) are tested against fakes for the pasteboard, hotkey registry, paste sender, app launcher, file watcher and clock.
- **Determinism rules:** no real sleeps or timers in tests (inject a clock and a manual scheduler), no real user data (temp directories only, cleaned up), no shared global state between tests, no dependence on test order, no network. The whole suite must pass when run repeatedly; the builder should run it several times in a row to prove it.
- **Memory check:** a separate script, not part of the unit suite (real memory varies from run to run). It launches the built app, measures `phys_footprint` idle, with the launcher open, and with the clipboard open showing a 2560×1600 screenshot, and fails if over budget (10 / 30 MB).
- **Latency check:** a separate script or instrumented build that reports hotkey→visible and keystroke→results times against §2.4 targets.

## 10. Left to the builder

- The exact fuzzy-scoring formula and frecency decay, as long as ranking feels right with the examples in §5.2.
- Clipboard poll interval.
- Storage format (e.g. JSON index plus image files).
- Thumbnail sizes and icon cache size, within the memory budget.
- A size cap for very large text copies (cap stored or previewed size so a huge copy can't blow the memory budget).
- Exact pixel spacing, within the mockups' look.
- Internal module and file names.

## 11. Calls made by the designer (not explicitly requested by the owner)

- Usage-based ranking (frecency) and the empty-query "most used" list.
- Clipboard grouped by day, with source app shown.
- Rich-text fidelity on paste.
- Fallback when Accessibility isn't granted (copy only).
- Menu bar icon (hideable); no Dock icon.
- Launch at login on by default.
- Dark appearance only.
- Minimum macOS 15.
- Memory and latency checks as separate scripts rather than unit tests.
