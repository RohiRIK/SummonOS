# macctl README demo, recorded with vhs (https://github.com/charmbracelet/vhs).
#
#   tools/record-demos.sh          # preferred: also refreshes the transcripts and SVG cards
#   vhs macctl/docs/demo/demo.tape # from the repo root, on a Mac with macctl on PATH
#
# Read-only on purpose: doctor, list, describe, get, diff and a --dry-run. Nothing on the Mac changes.
# The hidden setup wraps macctl so its output is the human (terminal) form, with $HOME and any
# pattern from tools/private-patterns.txt (passed in by record-demos.sh as a sed script) replaced.

Output macctl/docs/demo/demo.gif
Require macctl

Set Shell zsh
Set FontFamily "JetBrains Mono"
Set FontSize 15
Set Width 1180
Set Height 620
Set Padding 28
Set TypingSpeed 35ms
Set Theme { "name": "Summon Night", "background": "#0E0B1A", "foreground": "#E4DEF7", "selection": "#2B2347", "cursor": "#F6F3FF", "black": "#1A1530", "red": "#FF6B8B", "green": "#7CF2B0", "yellow": "#FFD479", "blue": "#7AA8FF", "purple": "#D18BFF", "cyan": "#3DE1FF", "white": "#E4DEF7", "brightBlack": "#5C567A", "brightRed": "#FF8FA6", "brightGreen": "#A3F7C9", "brightYellow": "#FFE2A3", "brightBlue": "#A2C2FF", "brightPurple": "#E2B2FF", "brightCyan": "#8AEDFF", "brightWhite": "#F6F3FF" }

Hide
Type `cd macctl && macctl() { script -q /dev/null macctl "$@" | tr -d '\r' | sed -E -f "${MACCTL_DEMO_SED:-/dev/null}" | sed "s|$HOME|/Users/you|g"; } && PS1='%F{141}$%f ' && clear`
Enter
Sleep 500ms
Show

Type "macctl doctor"
Enter
Sleep 2.5s

Type "macctl list --domain dock"
Enter
Sleep 3s

Type "macctl describe dock.tilesize"
Enter
Sleep 3s

Type "clear"
Enter
Type "macctl get dock.autohide dock.tilesize --json"
Enter
Sleep 3s

Type "clear"
Enter
Type "macctl diff profiles/default.json"
Enter
Sleep 3.5s

Type "macctl set dock.autohide true --dry-run"
Enter
Sleep 4s
