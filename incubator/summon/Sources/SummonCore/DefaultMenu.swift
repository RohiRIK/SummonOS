/// The menu Summon ships with. `summon menu init` writes it to `~/.config/summon/menu.jsonc`,
/// where the user owns it; the app falls back to this copy when that file is missing or broken.
/// Kept in Swift rather than as a bundle resource so the bundled `.app` never misses it.
public enum DefaultMenu {
    public static let jsonc = #"""
    // Summon Menu. Dotted ids define the tree (style.theme lives under style).
    // action: shell command run in your login shell. when / checked: shell guards (exit 0 = yes).
    {
      "items": [
        { "id": "agent", "label": "Agent", "icon": "sparkles", "aliases": ["ai", "ask"] },
        { "id": "agent.ask", "label": "Ask Agent", "icon": "sparkles", "action": "summon agent", "aliases": ["claude", "codex"] },
        { "id": "agent.task", "label": "Schedule a Task…", "icon": "clock.arrow.circlepath", "aliases": ["schedule", "recurring", "every", "cron"], "action": "summon task new" },
        { "id": "agent.diagnose", "label": "Diagnose Last Crash", "icon": "stethoscope", "action": "summon crash diagnose --latest", "aliases": ["crash", "fix"] },
        { "id": "agent.fix", "label": "Fix Issues with AI", "icon": "wrench.and.screwdriver", "action": "summon fix", "aliases": ["repair", "health", "doctor"] },
        { "id": "agent.debug", "label": "Save Debug Bundle", "icon": "doc.text.magnifyingglass", "action": "summon debug --save", "aliases": ["logs", "debug"] },
        { "id": "agent.undo", "label": "Undo Last Agent Session", "icon": "arrow.uturn.backward", "action": "summon undo-session", "aliases": ["revert", "rollback"] },
        { "id": "agent.default", "label": "Default Agent", "icon": "person.crop.circle" },
        { "id": "agent.default.claude", "label": "Claude Code", "icon": "c.circle", "when": "command -v claude", "checked": "[ \"$(summon default agent)\" = claude ]", "action": "summon default agent claude" },
        { "id": "agent.default.codex", "label": "Codex", "icon": "chevron.left.forwardslash.chevron.right", "when": "command -v codex", "checked": "[ \"$(summon default agent)\" = codex ]", "action": "summon default agent codex" },
        { "id": "agent.default.opencode", "label": "OpenCode", "icon": "terminal", "when": "command -v opencode", "checked": "[ \"$(summon default agent)\" = opencode ]", "action": "summon default agent opencode" },
        { "id": "agent.default.copilot", "label": "GitHub Copilot", "icon": "person.2", "when": "command -v copilot", "checked": "[ \"$(summon default agent)\" = copilot ]", "action": "summon default agent copilot" },
        { "id": "agent.default.cursor-agent", "label": "Cursor CLI", "icon": "cursorarrow.rays", "when": "command -v cursor-agent", "checked": "[ \"$(summon default agent)\" = cursor-agent ]", "action": "summon default agent cursor-agent" },
        { "id": "agent.default.agy", "label": "Antigravity", "icon": "airplane", "when": "command -v agy", "checked": "[ \"$(summon default agent)\" = agy ]", "action": "summon default agent agy" },
        { "id": "agent.default.pi", "label": "Pi", "icon": "p.circle", "when": "command -v pi", "checked": "[ \"$(summon default agent)\" = pi ]", "action": "summon default agent pi" },
        { "id": "agent.default.grok", "label": "Grok", "icon": "bolt", "when": "command -v grok", "checked": "[ \"$(summon default agent)\" = grok ]", "action": "summon default agent grok" },

        { "id": "style", "label": "Style", "icon": "paintpalette", "aliases": ["look", "appearance"] },
        { "id": "style.theme", "label": "Theme", "icon": "swatchpalette", "aliases": ["themes", "colors"] },
        { "id": "style.theme.summon-night", "label": "Summon Night", "icon": "moon.stars", "checked": "[ \"$(cat ~/.config/summon/current-theme 2>/dev/null)\" = summon-night ]", "action": "summon theme set summon-night" },
        { "id": "style.theme.tokyo-night", "label": "Tokyo Night", "icon": "moon", "checked": "[ \"$(cat ~/.config/summon/current-theme 2>/dev/null)\" = tokyo-night ]", "action": "summon theme set tokyo-night" },
        { "id": "style.theme.catppuccin", "label": "Catppuccin", "icon": "cup.and.saucer", "checked": "[ \"$(cat ~/.config/summon/current-theme 2>/dev/null)\" = catppuccin ]", "action": "summon theme set catppuccin" },
        { "id": "style.theme.gruvbox", "label": "Gruvbox", "icon": "leaf", "checked": "[ \"$(cat ~/.config/summon/current-theme 2>/dev/null)\" = gruvbox ]", "action": "summon theme set gruvbox" },
        { "id": "style.dark", "label": "Dark Mode", "icon": "circle.lefthalf.filled", "when": "command -v macctl", "action": "macctl set appearance.dark-mode true" },
        { "id": "style.light", "label": "Light Mode", "icon": "sun.max", "when": "command -v macctl", "action": "macctl set appearance.dark-mode false" },
        { "id": "style.screensaver", "label": "Start Screensaver", "icon": "sparkles.tv", "action": "open -a ScreenSaverEngine" },

        { "id": "setup", "label": "Setup", "icon": "gearshape", "aliases": ["settings", "preferences"] },
        { "id": "setup.profile-diff", "label": "Show Profile Drift", "icon": "arrow.left.arrow.right", "when": "command -v macctl", "action": "summon agent prompt 'Run macctl diff on my profile and explain what differs.'" },
        { "id": "setup.doctor", "label": "Check Permissions", "icon": "checkmark.shield", "when": "command -v macctl", "action": "summon agent prompt 'Run macctl doctor and walk me through anything missing.'" },
        { "id": "setup.fix", "label": "Fix Issues with AI", "icon": "wrench.and.screwdriver", "action": "summon fix", "aliases": ["doctor", "repair", "health"] },
        { "id": "setup.menu", "label": "Edit This Menu", "icon": "list.bullet.rectangle", "action": "summon menu init && open -t ~/.config/summon/menu.jsonc" },
        { "id": "setup.hooks", "label": "Open Hooks Folder", "icon": "folder", "action": "mkdir -p ~/.config/summon/hooks && open ~/.config/summon/hooks" },
        { "id": "setup.system-settings", "label": "System Settings", "icon": "gear", "action": "open -b com.apple.systempreferences" },

        { "id": "trigger", "label": "Trigger", "icon": "bolt", "aliases": ["capture", "toggle"] },
        { "id": "trigger.screenshot", "label": "Screenshot Area", "icon": "camera.viewfinder", "action": "screencapture -i -c", "aliases": ["capture"] },
        { "id": "trigger.screenshot-file", "label": "Screenshot to Desktop", "icon": "camera", "action": "screencapture -i ~/Desktop/Screenshot-$(date +%Y%m%d-%H%M%S).png" },
        { "id": "trigger.stay-awake", "label": "Stay Awake for 1 Hour", "icon": "cup.and.heat.waves", "action": "caffeinate -d -t 3600 &" },
        { "id": "trigger.lock", "label": "Lock Screen", "icon": "lock", "action": "pmset displaysleepnow" },

        { "id": "make", "label": "Make Something", "icon": "hammer", "aliases": ["create", "new", "build"] },
        { "id": "make.menubar", "label": "New Menu Bar App", "icon": "menubar.rectangle", "action": "summon agent prompt 'Make me a new menu bar app. Ask what it should show first and agree a short kebab-case name with me, then run summon project new <name> --kind menubar and build it in that folder, following the mac-app skill.'" },
        { "id": "make.app", "label": "New App", "icon": "macwindow", "action": "summon agent prompt 'Make me a new Mac app with its own window. Ask what it should do first and agree a short kebab-case name with me, then run summon project new <name> --kind app and build it in that folder, following the mac-app skill.'" },
        { "id": "make.cli", "label": "New Command-Line Tool", "icon": "terminal", "aliases": ["cli", "script"], "action": "summon agent prompt 'Make me a new command-line tool. Ask what it should do first and agree a short kebab-case name with me, then run summon project new <name> --kind cli and build it in that folder, following the mac-app skill.'" },
        { "id": "make.screensaver", "label": "New Screensaver", "icon": "sparkles.tv", "action": "summon agent prompt 'Make me a new screensaver. Ask what it should show first and agree a short kebab-case name with me, then run summon project new <name> --kind screensaver and build it in that folder, following the mac-app skill.'" },
        { "id": "make.theme", "label": "New Theme", "icon": "paintbrush", "action": "summon agent prompt 'Make me a new Summon theme. Ask for a mood or an image first, then use the summon-art skill for the palette and wallpaper and the summon-mac skill to install it.'" },
        { "id": "make.wallpaper", "label": "New Wallpaper", "icon": "photo.artframe", "aliases": ["background", "desktop"], "action": "summon agent prompt 'Make me a new wallpaper for the current Summon theme. Ask for a mood first, then follow the summon-art skill (wallpapers guide).'" },
        { "id": "make.icon", "label": "New Icon", "icon": "app.badge", "action": "summon agent prompt 'Make me a new icon. Ask what it is for and where to put it, then follow the summon-art skill (icons guide) and the mac-app skill to package and place it.'" },

        { "id": "install", "label": "Install", "icon": "shippingbox", "aliases": ["brew", "app"] },
        { "id": "install.ghostty", "label": "Ghostty", "icon": "terminal", "when": "! test -d /Applications/Ghostty.app", "action": "summon agent prompt 'Install Ghostty with Homebrew and set it up with the current Summon theme.'" },
        { "id": "install.kitty", "label": "kitty", "icon": "cat", "when": "! test -d /Applications/kitty.app", "action": "summon agent prompt 'Install kitty with Homebrew (brew install --cask kitty), add include ~/.config/summon/generated/kitty.conf to ~/.config/kitty/kitty.conf so it follows the Summon theme, then ask me whether agents should open in kitty (summon default terminal kitty).'" },
        { "id": "install.aerospace", "label": "AeroSpace Tiling", "icon": "rectangle.split.3x1", "when": "! command -v aerospace", "action": "summon agent prompt 'Install AeroSpace with Homebrew and set it up with the Summon keymap.'" },
        { "id": "install.borders", "label": "Window Borders", "icon": "square.dashed", "when": "! command -v borders", "action": "summon agent prompt 'Install JankyBorders with Homebrew and color it from the current Summon theme.'" },

        { "id": "update", "label": "Update", "icon": "arrow.triangle.2.circlepath", "aliases": ["upgrade"] },
        { "id": "update.brew", "label": "Update Homebrew Apps", "icon": "shippingbox.circle", "when": "command -v brew", "action": "summon agent prompt 'Run brew update and brew upgrade, then tell me what changed and whether anything failed.'" },
        { "id": "update.macos", "label": "Check for macOS Updates", "icon": "apple.logo", "action": "open 'x-apple.systempreferences:com.apple.Software-Update-Settings.extension'" },

        { "id": "system", "label": "System", "icon": "power", "aliases": ["power"] },
        { "id": "system.sleep", "label": "Sleep", "icon": "moon.zzz", "action": "pmset sleepnow" },
        { "id": "system.restart", "label": "Restart…", "icon": "restart", "action": "osascript -e 'tell application \"System Events\" to restart'" },
        { "id": "system.logout", "label": "Log Out…", "icon": "rectangle.portrait.and.arrow.right", "action": "osascript -e 'tell application \"System Events\" to log out'" },
        { "id": "system.shutdown", "label": "Shut Down…", "icon": "power", "action": "osascript -e 'tell application \"System Events\" to shut down'" }
      ]
    }
    """#
}
