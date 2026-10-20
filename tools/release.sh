#!/usr/bin/env bash
# Build the exact, already published public commit; upload checksum and source provenance.
# Usage: tools/release.sh plugins/<name> ["extra release notes"]
# Optional production distribution: set BOTH SUMMON_SIGN_IDENTITY and SUMMON_NOTARY_PROFILE.
# See tools/notarize-app.sh for identity/profile/entitlements inputs. Preview is the default.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PRODUCTION=0
if [[ -n ${SUMMON_SIGN_IDENTITY:-} || -n ${SUMMON_NOTARY_PROFILE:-} ]]; then
  [[ -n ${SUMMON_SIGN_IDENTITY:-} && -n ${SUMMON_NOTARY_PROFILE:-} ]] || {
    echo "Production release requires both SUMMON_SIGN_IDENTITY and SUMMON_NOTARY_PROFILE." >&2; exit 1;
  }
  PRODUCTION=1
fi
PLUGIN=$(cd "${1:?plugin directory required}" && pwd)
EXTRA=${2:-}
NAME=$(basename "$PLUGIN")
USER_LOGIN=$(gh api user -q .login)
REPO="$USER_LOGIN/$NAME"
WORK=$(mktemp -d)
trap '/bin/rm -rf "$WORK"' EXIT

[[ $(git -C "$PLUGIN" branch --show-current) == main ]] || {
  echo "Release from main only." >&2; exit 1;
}
[[ -z $(git -C "$PLUGIN" status --porcelain --untracked-files=all) ]] || {
  echo "Release requires a clean working tree, including untracked source files." >&2; exit 1;
}
[[ $(gh repo view "$REPO" --json isPrivate --jq .isPrivate) == false ]] || {
  echo "Release target must be an existing public repository." >&2; exit 1;
}

git clone --quiet --depth 1 --branch main "https://github.com/$REPO.git" "$WORK/public"
SOURCE_SHA=$(git -C "$WORK/public" rev-parse HEAD)
mkdir "$WORK/local-source" "$WORK/source"
git -C "$PLUGIN" archive HEAD | tar -x -C "$WORK/local-source"
git -C "$WORK/public" archive "$SOURCE_SHA" | tar -x -C "$WORK/source"
/bin/rm -f "$WORK/local-source/PROJECT-CONTEXT.md"
if ! diff -qr "$WORK/local-source" "$WORK/source" >/dev/null; then
  echo "Local main differs from public $SOURCE_SHA. Publish the reviewed source before releasing." >&2
  exit 1
fi

PLIST="$WORK/source/Resources/Info.plist"
APP=$(plutil -extract CFBundleExecutable raw -o - "$PLIST")
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")
[[ $APP =~ ^[A-Za-z0-9][A-Za-z0-9._\ -]*$ && $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || {
  echo "Invalid app executable name or release version." >&2; exit 1;
}
# Build exported public source: unpublished local files and build output cannot enter.
"$WORK/source/scripts/check.sh"
codesign --verify --deep --strict "$WORK/source/build/$APP.app"
mkdir -p "$PLUGIN/build"
ZIP="$PLUGIN/build/$APP-$VERSION.zip"
if [[ $PRODUCTION -eq 1 ]]; then
  bash "$ROOT/tools/notarize-app.sh" "$WORK/source/build/$APP.app" "$WORK/production"
  mv "$WORK/production/$APP.zip" "$WORK/$APP-$VERSION.zip"
  INSTALL_NOTES="This app is signed with Developer ID, notarized by Apple and includes a validated stapled ticket."
else
  ditto -c -k --keepParent "$WORK/source/build/$APP.app" "$WORK/$APP-$VERSION.zip"
  INSTALL_NOTES="These preview builds are ad-hoc signed and are not notarized by Apple. macOS may block the first launch;
review the source and publisher before choosing **Open Anyway** in System Settings › Privacy & Security."
fi
mv "$WORK/$APP-$VERSION.zip" "$ZIP"
(
  cd "$PLUGIN/build"
  shasum -a 256 "$APP-$VERSION.zip" >SHA256SUMS
)
cat >"$PLUGIN/build/release-source.txt" <<EOF
Repository: https://github.com/$REPO
Commit: $SOURCE_SHA
Version: $VERSION
Artifact: $APP-$VERSION.zip
Production signing: $PRODUCTION
EOF
cat >"$WORK/notes.md" <<EOF
${EXTRA:+$EXTRA

}Built from public source commit \`$SOURCE_SHA\`. Verify the download against \`SHA256SUMS\`.

## Install

Download \`$APP-$VERSION.zip\`, unzip, and move \`$APP.app\` to Applications.
$INSTALL_NOTES
Minimum macOS version and supported architectures are declared by the app's source and bundle.
EOF
gh release create "v$VERSION" "$ZIP" "$PLUGIN/build/SHA256SUMS" "$PLUGIN/build/release-source.txt" \
  -R "$REPO" --target "$SOURCE_SHA" --title "$APP $VERSION" --notes-file "$WORK/notes.md"
