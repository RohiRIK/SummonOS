# Settings catalog

Source of truth: `Sources/MacCtlCore/Catalog.swift`. `macctl describe <id>` shows the full schema.
"Verified" means a human applied and undid the setting on a real Mac and stamped `verifiedOn`.

| id | domain / key | type | side effect | verified |
|---|---|---|---|---|
| `dock.autohide` | `com.apple.dock` / `autohide` | bool | restart Dock | no |
| `dock.tilesize` | `com.apple.dock` / `tilesize` | int 16...128 | restart Dock | no |
| `dock.show-recents` | `com.apple.dock` / `show-recents` | bool | restart Dock | no |
| `dock.orientation` | `com.apple.dock` / `orientation` | enum left, bottom, right | restart Dock | no |
| `dock.minimize-effect` | `com.apple.dock` / `mineffect` | enum genie, scale, suck | restart Dock | no |
| `dock.autohide-delay` | `com.apple.dock` / `autohide-delay` | double 0...5 (seconds) | restart Dock | no |
| `finder.show-extensions` | `NSGlobalDomain` / `AppleShowAllExtensions` | bool | restart Finder | no |
| `finder.show-pathbar` | `com.apple.finder` / `ShowPathbar` | bool | restart Finder | no |
| `finder.show-statusbar` | `com.apple.finder` / `ShowStatusBar` | bool | restart Finder | no |
| `finder.default-view` | `com.apple.finder` / `FXPreferredViewStyle` | enum Nlsv, icnv, clmv, glyv | restart Finder | no |
| `finder.show-hidden` | `com.apple.finder` / `AppleShowAllFiles` | bool | restart Finder | no |
| `keyboard.key-repeat` | `NSGlobalDomain` / `KeyRepeat` | int 1...120 (x 15 ms) | logout | no |
| `keyboard.initial-key-repeat` | `NSGlobalDomain` / `InitialKeyRepeat` | int 10...120 (x 15 ms) | logout | no |
| `keyboard.press-and-hold` | `NSGlobalDomain` / `ApplePressAndHoldEnabled` | bool | logout | no |
| `screenshots.location` | `com.apple.screencapture` / `location` | path | restart SystemUIServer | no |
| `screenshots.format` | `com.apple.screencapture` / `type` | enum png, jpg, pdf, heic, tiff | restart SystemUIServer | no |
| `screenshots.disable-shadow` | `com.apple.screencapture` / `disable-shadow` | bool | restart SystemUIServer | no |
| `appearance.dark-mode` | AppleScript: System Events `appearance preferences` / `dark mode` (Automation permission) | bool | none | no |

Finder view codes: `Nlsv` list, `icnv` icons, `clmv` columns, `glyv` gallery.
