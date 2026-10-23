# Settings catalog

Source of truth: `Sources/MacCtlCore/Catalog.swift`. `macctl describe <id>` shows the full schema.
"Verified" means a human applied and undid the setting on a real Mac and stamped `verifiedOn`.

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
| `windows.click-desktop-to-reveal` | `com.apple.WindowManager` / `EnableStandardClickToShowDesktop` | bool | none | no | 15+ |
| `windows.tile-by-edge-drag` | `com.apple.WindowManager` / `EnableTilingByEdgeDrag` | bool | none | no | 15+ |
| `windows.tile-margins` | `com.apple.WindowManager` / `EnableTiledWindowMargins` | bool | none | no | 15+ |
| `menubar.agent` | `NSGlobalDomain` / `NSMenuEnableMenuBarAgent` | bool | logout | no | 27+ |
| `menubar.keyboard-navigation` | `NSGlobalDomain` / `NSMenuBarUseAgentNavigation` | bool | logout | no | 27+ |
| `documents.save-to-icloud` | `NSGlobalDomain` / `NSDocumentSaveNewDocumentsToCloud` | bool | relaunch apps | no | 15+ |
| `documents.autocorrect` | `NSGlobalDomain` / `NSAutomaticSpellingCorrectionEnabled` | bool | relaunch apps | no | 15+ |

`desktop.wallpaper` refuses a missing file or a folder before anything is written (also on undo, if the
old picture was deleted since). It has no system default, so `reset` is unsupported; `undo` restores the
previous picture.

Finder view codes: `Nlsv` list, `icnv` icons, `clmv` columns, `glyv` gallery.

`menubar.keyboard-navigation` (macOS 27, hidden) moves with the arrow keys from the app's last menu into the
status menus; it needs `menubar.agent` on as well, and both take effect after logout (source: MacG, 2026-08).

macOS 27's Liquid Glass slider (System Settings > Appearance) has no published preference key yet. Find it on a
Mac with `macctl discover start`, move the slider, then `macctl discover diff`, and add the key here once verified.
Writing `/Library/Preferences/FeatureFlags` (root, reboot) is out of scope for macctl.
