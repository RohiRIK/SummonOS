---
description: Make an icon and put it on an app, file, folder, or the Dock
argument-hint: <what the icon should look like> [for <path or app>]
---

Icon request: $ARGUMENTS

Use the `mac-app` skill, Icons section. Make a 1024×1024 master on Apple's icon grid in the current Summon
theme's colors, export `.icns` with `iconutil` (and a template PNG if it is for the menu bar). If a target is
given, apply it with `NSWorkspace.setIcon` (a tiny Swift script or `summon icon set <image> <path>` if present),
tell the user how to undo it (Get Info → select the icon → Delete), and for apps in `/Applications` warn that
an app update resets it.
