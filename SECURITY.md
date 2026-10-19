# Security policy

SummonOS runs agents with real power on your Mac: Summon starts coding agents that can run commands, and
`macctl` changes system settings. We take reports about that seriously.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through GitHub instead:
**[Security → Report a vulnerability](https://github.com/RohiRIK/SummonOS/security/advisories/new)**.

Include what you found, how to reproduce it, the macOS version and the commit you tested, and what an attacker
could do with it. We aim to acknowledge a report within a few days and will keep you posted until it is fixed.
This is a small personal project, so there is no bug bounty, but we are glad to credit you in the fix.

## Supported versions

Only the latest `main` is supported. SummonOS has no releases yet; fixes land on `main`, and you update by
running `install.sh` again.

## What is in scope

- `install.sh` and `docs/install-ai.md`: anything that makes the installer run code or change files it should not.
- `macctl`: a setting changed without a snapshot, an `undo` that restores the wrong value, or a way to make it
  write outside the settings it declares.
- Summon: checkpoints and undo that fail silently, crash or log handoff that leaks data to the wrong place,
  the `summon://` URL scheme, the hotkey launcher, or the native dialog that guards creating a GitHub repo.
- Secrets or personal data committed to this repository.

## Out of scope

- What an agent does once you run it in auto mode on your own request. Summon checkpoints each session so you
  can undo it; it does not sandbox the agent. Report it if the checkpoint or undo itself is broken.
- Vulnerabilities in third-party agents (Claude Code, Codex and others) or tools installed through Homebrew;
  please report those to their maintainers.
