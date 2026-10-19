---
description: Build a new command-line tool for this Mac
argument-hint: <what the tool should do>
---

Build a new command-line tool that does this: $ARGUMENTS

Agree a short kebab-case name with the user (it becomes the command), then start it from Summon's template:
`summon project new <name> --kind cli`. It lands in `~/Summon/Apps/<name>` with argument parsing in a tested Core and
`main.swift` kept thin; work in that folder. Use the `mac-app` skill's rules (Swift 6, no third-party dependencies,
tools by absolute path with argv arrays). Plain text for people, `--json` for agents once there is data worth
parsing; exit codes 0 ok, 1 error, 2 usage. Done when `scripts/check.sh` passes; `scripts/install.sh` puts it in
`~/.local/bin`. It also gets its private GitHub repo (screenshots, CI): if `summon project new` says there is no repo yet, fix the
cause and run `summon project repo <name>`. Never create or publish a repo yourself.
