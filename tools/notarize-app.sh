#!/usr/bin/env bash
# Sign and notarize a COPY of an existing app, leaving the original build untouched.
# SUMMON_SIGN_IDENTITY='Developer ID Application: Name (TEAMID1234)'
# SUMMON_NOTARY_PROFILE=<existing notarytool keychain profile>
# Optional SUMMON_SIGN_ENTITLEMENTS=<reviewed app entitlements plist>; no credentials are stored here.
# Usage: tools/notarize-app.sh path/to/App.app output-directory
set -euo pipefail

APP=$(cd "${1:?built app required}" && pwd)
OUTPUT=${2:?output directory required}
IDENTITY=${SUMMON_SIGN_IDENTITY:?Developer ID Application identity required}
PROFILE=${SUMMON_NOTARY_PROFILE:?Existing notarytool keychain profile required}
[[ $APP == *.app && -d $APP/Contents/MacOS && ! -L ${1} ]] || {
  echo "Provide a built app directory, not a symlink." >&2; exit 1;
}
[[ $IDENTITY =~ ^Developer\ ID\ Application:\ .+\ \([A-Z0-9]{10}\)$ ]] || {
  echo "Production signing requires a Developer ID Application identity." >&2; exit 1;
}
# Verify the exact named identity exists locally before touching a copy or contacting Apple.
security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null || {
  echo "The requested Developer ID identity is not available in the keychain." >&2; exit 1;
}
if [[ -n ${SUMMON_SIGN_ENTITLEMENTS:-} ]]; then
  [[ -f $SUMMON_SIGN_ENTITLEMENTS ]] || { echo "Entitlements file is missing." >&2; exit 1; }
  plutil -lint "$SUMMON_SIGN_ENTITLEMENTS" >/dev/null
fi
WORK=$(mktemp -d)
trap '/bin/rm -rf "$WORK"' EXIT
NAME=$(basename "$APP" .app)
STAGED="$WORK/$NAME.app"
cp -R "$APP" "$STAGED"

# Sign Mach-O leaves first, including the bundled summon CLI and any dynamic libraries.
find "$STAGED/Contents" -type f -print0 >"$WORK/files"
while IFS= read -r -d '' executable; do
  description=$(file -b "$executable")
  if [[ $description == *Mach-O* ]]; then
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$executable"
  fi
done <"$WORK/files"
# Nested bundles require inside-out signing; do not use --deep as a signing shortcut.
find "$STAGED/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' \) -print0 >"$WORK/bundles"
while IFS= read -r -d '' bundle; do
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$bundle"
done <"$WORK/bundles"
if [[ -n ${SUMMON_SIGN_ENTITLEMENTS:-} ]]; then
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$SUMMON_SIGN_ENTITLEMENTS" "$STAGED"
else
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$STAGED"
fi
codesign --verify --deep --strict "$STAGED"
ditto -c -k --keepParent "$STAGED" "$WORK/submission.zip"
xcrun notarytool submit "$WORK/submission.zip" --keychain-profile "$PROFILE" --wait --output-format json >"$WORK/notary.json"
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("status") == "Accepted" else "Notarization was not accepted; no production artifact created.")' "$WORK/notary.json"
xcrun stapler staple "$STAGED"
xcrun stapler validate "$STAGED"
codesign --verify --deep --strict "$STAGED"
spctl --assess --type execute --verbose=2 "$STAGED"
# Repackage AFTER stapling; the submission archive does not contain the ticket.
ditto -c -k --keepParent "$STAGED" "$WORK/$NAME.zip"
mkdir -p "$OUTPUT"
mv "$WORK/$NAME.zip" "$OUTPUT/$NAME.zip"
(
  cd "$OUTPUT"
  shasum -a 256 "$NAME.zip" >SHA256SUMS
)
echo "Verified production artifact: $OUTPUT/$NAME.zip"
