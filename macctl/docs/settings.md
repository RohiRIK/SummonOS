---
type: reference
title: macctl settings catalog
description: All 39 typed macOS settings, availability, side effects and per-backend recovery limits.
tags: [macctl, settings, reference]
---

# Settings catalog

Source of truth: [`Catalog.swift`](../Sources/MacCtlCore/Catalog.swift). `macctl describe <id>` shows
the full schema and recovery contract; `macctl list --domain <name>` reads one catalog group.
See the [macctl CLI reference](../README.md), [documentation home](../../docs/home.md) and
[security/recovery model](../../docs/security-model.md).

The current source contains **39 settings across 9 domains**: Dock 11, Finder 8, keyboard 3,
screenshots 5, appearance 4, desktop 1, windows 3, menubar 2 and documents 2. All have `user` risk.
All `verifiedOn` arrays are empty: a catalog entry is implemented, not a claim of per-key live
acceptance on every supported macOS. "Verified" is set only when a human records a real-Mac
check in `verifiedOn`; the targeted historical accent evidence below does not change those stamps.
The macOS column reflects declared availability gates, not a tested OS matrix.

## Settings

| id | domain / key | type | side effect | verified | macOS |
|---|---|---|---|---|---|
| `dock.autohide` | `com.apple.dock` / `autohide` | bool | restart Dock | no | 15+ |
| `dock.tilesize` | `com.apple.dock` / `tilesize` | int 16...128 | restart Dock | no | 15+ |
| `dock.show-recents` | `com.apple.dock` / `show-recents` | bool | restart Dock | no | 15+ |
| `dock.orientation` | `com.apple.dock` / `orientation` | enum left, bottom, right | restart Dock | no | 15+ |
| `dock.minimize-effect` | `com.apple.dock` / `mineffect` | enum genie, scale, suck | restart Dock | no | 15+ |
| `dock.autohide-delay` | `com.apple.dock` / `autohide-delay` | double 0...5 (seconds) | restart Dock | no | 15+ |
| `finder.show-extensions` | `NSGlobalDomain` / `AppleShowAllExtensions` | bool | restart Finder | no | 15+ |
| `finder.show-pathbar` | `com.apple.finder` / `ShowPathbar` | bool | restart Finder | no | 15+ |
| `finder.show-statusbar` | `com.apple.finder` / `ShowStatusBar` | bool | restart Finder | no | 15+ |
| `finder.default-view` | `com.apple.finder` / `FXPreferredViewStyle` | enum Nlsv, icnv, clmv, glyv | restart Finder | no | 15+ |
| `finder.show-hidden` | `com.apple.finder` / `AppleShowAllFiles` | bool | restart Finder | no | 15+ |
| `keyboard.key-repeat` | `NSGlobalDomain` / `KeyRepeat` | int 1...120 (x 15 ms) | logout | no | 15+ |
| `keyboard.initial-key-repeat` | `NSGlobalDomain` / `InitialKeyRepeat` | int 10...120 (x 15 ms) | logout | no | 15+ |
| `keyboard.press-and-hold` | `NSGlobalDomain` / `ApplePressAndHoldEnabled` | bool | logout | no | 15+ |
| `screenshots.location` | `com.apple.screencapture` / `location` | path | restart SystemUIServer | no | 15+ |
| `screenshots.format` | `com.apple.screencapture` / `type` | enum png, jpg, pdf, heic, tiff | restart SystemUIServer | no | 15+ |
| `screenshots.disable-shadow` | `com.apple.screencapture` / `disable-shadow` | bool | restart SystemUIServer | no | 15+ |
| `appearance.dark-mode` | AppleScript: System Events `appearance preferences` / `dark mode` (Automation permission) | bool | none | no | 15+ |
| `desktop.wallpaper` | `NSWorkspace` desktop image: reads the main screen, sets every screen | path (existing file) | none | no | 15+ |
| `dock.magnification` | `com.apple.dock` / `magnification` | bool | restart Dock | no | 15+ |
| `dock.magnified-size` | `com.apple.dock` / `largesize` | int 16...512 | restart Dock | no | 15+ |
| `dock.show-indicators` | `com.apple.dock` / `show-process-indicators` | bool | restart Dock | no | 15+ |
| `dock.only-open-apps` | `com.apple.dock` / `static-only` | bool | restart Dock | no | 15+ |
| `dock.autohide-speed` | `com.apple.dock` / `autohide-time-modifier` | double 0...5 (seconds) | restart Dock | no | 15+ |
| `finder.folders-first` | `com.apple.finder` / `_FXSortFoldersFirst` | bool | restart Finder | no | 15+ |
| `finder.warn-extension-change` | `com.apple.finder` / `FXEnableExtensionChangeWarning` | bool | restart Finder | no | 15+ |
| `finder.search-scope` | `com.apple.finder` / `FXDefaultSearchScope` | enum SCev, SCcf, SCsp | restart Finder | no | 15+ |
| `screenshots.show-thumbnail` | `com.apple.screencapture` / `show-thumbnail` | bool | restart SystemUIServer | no | 15+ |
| `screenshots.include-date` | `com.apple.screencapture` / `include-date` | bool | restart SystemUIServer | no | 15+ |
| `appearance.scroll-bars` | `NSGlobalDomain` / `AppleShowScrollBars` | enum Automatic, WhenScrolling, Always | relaunch apps | no | 15+ |
| `appearance.menu-icons` | `NSGlobalDomain` / `NSMenuEnableActionImages` | bool | relaunch apps | no | 26+ |
| `appearance.accent-color` | `NSGlobalDomain` / `AppleAccentColor` | int -1…6 (unset = multicolor) | notify running apps; reopen if cached | no | 15+ |
| `windows.click-desktop-to-reveal` | `com.apple.WindowManager` / `EnableStandardClickToShowDesktop` | bool | none | no | 15+ |
| `windows.tile-by-edge-drag` | `com.apple.WindowManager` / `EnableTilingByEdgeDrag` | bool | none | no | 15+ |
| `windows.tile-margins` | `com.apple.WindowManager` / `EnableTiledWindowMargins` | bool | none | no | 15+ |
| `menubar.agent` | `NSGlobalDomain` / `NSMenuEnableMenuBarAgent` | bool | logout | no | 27+ |
| `menubar.keyboard-navigation` | `NSGlobalDomain` / `NSMenuBarUseAgentNavigation` | bool | logout | no | 27+ |
| `documents.save-to-icloud` | `NSGlobalDomain` / `NSDocumentSaveNewDocumentsToCloud` | bool | relaunch apps | no | 15+ |
| `documents.autocorrect` | `NSGlobalDomain` / `NSAutomaticSpellingCorrectionEnabled` | bool | relaunch apps | no | 15+ |

## Appearance and folder colors

`appearance.accent-color` accepts `-1` graphite, `0` red, `1` orange, `2` yellow, `3` green,
`4` blue, `5` purple and `6` pink. An absent key means multicolor; there is no public `reset`
command or multicolor sentinel value. Undo restores an absent key by deleting the explicit preference.
For negative input use `macctl set appearance.accent-color -- -1`.

After committed accent changes, the active side effect posts both `AppleAquaColorVariantChanged`
and `AppleColorPreferencesChangedNotification`; restored changes refresh appearance during undo,
rollback and recovery too. No-op apply and dry-run do not trigger this effect. These are private
notification names, not a public macOS setter API, and clients retaining cached colors may need reopening.
macctl does not quit and relaunch apps automatically.

Finder's separate **Folder color** control follows the accent when set to **Automatic**. Explicit/custom
folder colors are preserved; macctl does not expose a folder-color preference or reset those choices.
[Apple documents the separate controls](https://support.apple.com/guide/mac-help/change-appearance-settings-mchlp1225/mac).

Historical evidence recorded with commit `dbcb4fb` on macOS 27.2: an already-running AppKit client
switched blue → purple → blue across apply/undo; native configuration readback resolved Automatic
to the changed accent, and `NSWorkspace` renders of an ordinary folder changed blue → purple.
That is targeted AppKit/configuration/icon-rendering evidence, **not an already-open Finder-window
screenshot**, comprehensive OS validation or a new runtime check in this documentation refresh.
Refresh research: [Chromium CoreUI note](https://chromium.googlesource.com/chromium/src.git/+/62.0.3202.58/content/renderer/theme_helper_mac.mm#31)
and [Monterey observation](https://alexwlchan.net/2022/changing-the-macos-accent-colour/); no upstream code copied.

## Recovery by backend

| Backend | Catalog settings | Restoration boundary |
|---|---|---|
| CFPreferences (`defaults` in schema) | 37 | Exact prior presence, CF type and value at the written user/host triple; absent/inherited priors delete that triple's explicit key. External inheritance/MDM changes are not undone. |
| AppleScript | `appearance.dark-mode` | Previous boolean value, not preference-key presence; requires Automation access to System Events. |
| `NSWorkspace` | `desktop.wallpaper` | Previous picture per recorded display UUID while each display is connected and its old file exists; legacy scalar snapshots retain scalar restoration. |

`desktop.wallpaper` reads the main screen and sets every current screen. It rejects a missing path or
directory before a mutation; undo/recovery cannot recreate a deleted picture. The backend waits up to
three seconds for screens to report target pictures before the engine verifies read-back. There is
no known system default and no public `reset` command.

Each setting's `recovery` field declares `restore`, `priorStates`, `verifiedByReadBack`, `handEdits`,
`notUndone` and `notes`. The engine journals intent before each write and reads back restoration;
this is an implementation contract, not a catalog `verifiedOn` stamp. Ordinary hand edits are left
alone with `partial_restore`. Force can overwrite eligible hand edits only by deliberate user choice;
it cannot restore a missing asset/display. Restarts, logout/relaunch requirements and folders created
for path settings are not undone. Screenshot files themselves are not moved or deleted by undo.
See [CLI safety and recovery](../README.md#safety) for unfinished sessions, corrupt journals and limits.

## Finder and newer macOS keys

Finder view codes: `Nlsv` list, `icnv` icons, `clmv` columns, `glyv` gallery.

`menubar.keyboard-navigation` (macOS 27, hidden) moves with the arrow keys from the app's last menu into the
status menus; it needs `menubar.agent` on as well, and both take effect after logout (source: MacG, 2026-08).

The current catalog has **no Liquid Glass slider setting**. No public preference key is documented
in this repository. On a Mac, `macctl discover start`, changing one control, then `macctl discover diff`
can identify candidate preference changes; absence of a diff does not prove a control has no state.
Discovery does not write preferences, but saves a private local baseline and can print changed values:
review output before sharing. Draft keys still need meaning, range, defaults and recovery validation
before catalog inclusion. Writing `/Library/Preferences/FeatureFlags` (root, reboot) is out of scope.
