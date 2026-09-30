#!/usr/bin/env bash
# Build a plugin and publish its .app as a zip on the PUBLIC repo's GitHub Releases.
# Run after the change is merged to main and published with tools/publish-public.sh.
#
#   tools/release.sh plugins/<name> ["extra release notes"]
#
# Version comes from Resources/Info.plist (CFBundleShortVersionString); tag is v<version>.
set -euo pipefail

readonly PLUGIN="$(cd "$1" && pwd)"
readonly EXTRA="${2:-}"
readonly NAME="$(basename "$PLUGIN")"
readonly PLIST="$PLUGIN/Resources/Info.plist"
readonly APP="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
readonly VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
readonly REPO="$(gh api user -q .login)/$NAME"
readonly ZIP="$PLUGIN/build/$APP-$VERSION.zip"
readonly WORK="$(mktemp -d)"
trap '/bin/rm -rf "$WORK"' EXIT

[[ "$(git -C "$PLUGIN" branch --show-current)" == main ]] || { echo "Release from main only." >&2; exit 1; }
"$PLUGIN/scripts/check.sh" >/dev/null || { echo "check.sh failed: see $PLUGIN/build/check-report.md" >&2; exit 1; }

/bin/rm -f "$ZIP"
ditto -c -k --keepParent "$PLUGIN/build/$APP.app" "$ZIP"  # keeps the signature and attributes

cat >"$WORK/notes.md" <<EOF
${EXTRA:+$EXTRA

}## Install

1. Download \`$APP-$VERSION.zip\` below and unzip it.
2. Move \`$APP.app\` to Applications and open it.
3. The app is not notarized by Apple, so macOS blocks the first launch. Open **System Settings ›
   Privacy & Security**, scroll down, and click **Open Anyway** next to $APP. Or in Terminal:
   \`xattr -dr com.apple.quarantine /Applications/$APP.app\`

macOS 15 or later, Apple silicon and Intel.
EOF

gh release create "v$VERSION" "$ZIP" -R "$REPO" --target main \
  --title "$APP $VERSION" --notes-file "$WORK/notes.md"
