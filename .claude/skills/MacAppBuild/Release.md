# Release

## Versioning

- `CFBundleShortVersionString` = user-facing semver (`0.2.0`); `CFBundleVersion` = build number,
  +1 every release (Sparkle and macOS compare it).
- Tag `v<version>` on `main` after the PR merges.

## Package

Merge to the dev repo's `main`, publish with `tools/publish-public.sh`, then:

```bash
tools/release.sh plugins/<name> "one-paragraph what's new"
```

It runs `scripts/check.sh`, zips `build/<App>.app` with `ditto -c -k --keepParent` (keeps the signature),
and creates `v<version>` on the **public** repo with install notes. `scripts/bundle.sh` builds a universal
binary (`--arch arm64 --arch x86_64`); check with `lipo -archs`. Verify the upload the way a user gets it:
`gh release download`, `ditto -x -k`, `codesign --verify --deep --strict`.

A DMG (`brew install create-dmg`) is nicer for drag-to-Applications, but a zip is enough for personal use.

## Signing and Gatekeeper

| Signing | Who can run it |
|---|---|
| Ad-hoc (`codesign --sign -`), current setup | This Mac. Other Macs: System Settings › Privacy & Security › **Open Anyway**, or `xattr -dr com.apple.quarantine <App>.app`. macOS 15 removed the right-click › Open bypass, so do not tell users to do that. |
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
