# Release

## Versioning

- `CFBundleShortVersionString` = user-facing semver (`0.2.0`); `CFBundleVersion` = build number,
  +1 every release (Sparkle and macOS compare it).
- Tag `v<version>` on `main` after the PR merges.

## Package

```bash
scripts/check.sh
ditto -c -k --keepParent build/<App>.app build/<App>-<version>.zip     # keeps signature + xattrs
gh release create v<version> build/<App>-<version>.zip --title "<App> <version>" --notes-file notes.md
```

A DMG (`brew install create-dmg`) is nicer for drag-to-Applications, but a zip is enough for personal use.

## Signing and Gatekeeper

| Signing | Who can run it |
|---|---|
| Ad-hoc (`codesign --sign -`), current setup | This Mac. Other Macs: right-click > Open, or `xattr -dr com.apple.quarantine <App>.app` |
| Developer ID + notarization (paid Apple Developer account) | Anyone, no warnings |

Notarization flow when an account exists: sign with `--options runtime` and the Developer ID
identity, `xcrun notarytool submit <zip> --keychain-profile <profile> --wait`, then
`xcrun stapler staple <App>.app`. Hardened runtime may need entitlements for some APIs.

## Updates

- Personal use: re-download from the GitHub release.
- Distributed apps: Sparkle 2 (SPM package), an `appcast.xml` signed with EdDSA, `SUFeedURL` and
  `SUPublicEDKey` in Info.plist. Needs Developer ID signing to be worth it.
  Reference: github.com/fayazara/macos-app-skills (`auto-update`, `release`); read it, but it has no
  license, so write our own code rather than copying theirs.
