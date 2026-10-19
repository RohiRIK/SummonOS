# Install SummonOS (instructions for an AI agent)

You are a coding agent (Claude Code, Codex, OpenCode, Cursor, or similar) running on the user's Mac, and the
user asked you to install SummonOS. Follow these steps in order. Stop and tell the user if a step fails;
do not work around a failure by changing system settings yourself.

## 1. Check the Mac

Run these and read the output:

```sh
sw_vers -productVersion      # needs 15 or newer
swift --version              # needs Swift 6 or newer
git --version
```

- macOS older than 15: stop and tell the user SummonOS needs macOS 15+.
- No Swift, or Swift older than 6: tell the user to install or update Xcode (or run
  `xcode-select --install`), then stop. Do not install Xcode yourself.

## 2. Install

```sh
curl -fsSL https://raw.githubusercontent.com/RohiRIK/macos-plugins/main/install.sh | bash
```

The script clones SummonOS into `~/.summonos`, builds `macctl` and Summon from source (a few minutes the first
time), installs `Summon.app` into `~/Applications`, links `summon` and `macctl` into `~/.local/bin`, and
links Summon's skills into every agent's skill folder. It is safe to run again.

If the user already has a checkout, run `./install.sh` from its root instead.

## 3. Make it usable

1. If `~/.local/bin` is not on `PATH`, add it to the user's shell profile (`~/.zshrc` on a default Mac):
   `export PATH="$HOME/.local/bin:$PATH"`. Tell the user you did.
2. Set yourself as Summon's default agent, using your own name from this list:
   `claude`, `codex`, `opencode`, `copilot`, `cursor`, `agy`, `pi`, `grok`.
   ```sh
   summon default agent <your-name>
   ```
3. Open the menu app: `open ~/Applications/Summon.app`.

## 4. Verify and report

```sh
summon doctor
macctl doctor
```

Tell the user, in a few lines:

- what was installed and where,
- anything `summon doctor` or `macctl doctor` reports as missing, with the exact fix it suggests
  (macOS permissions such as Automation or Accessibility can only be granted by the user, in System Settings),
- how to start: press ⌃⌥Space for Summon Menu, or run `summon` in a terminal.

## Rules while you do this

- Do not run anything with `sudo`.
- Do not change macOS settings during the install. After it, change them only through `macctl`, which
  snapshots each change so `macctl undo` can reverse it.
- Do not create GitHub repositories or publish anything.
