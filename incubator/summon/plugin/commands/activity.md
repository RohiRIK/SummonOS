---
description: Show what changed on this Mac recently and Summon's status
argument-hint: [settings|agent|checkpoint|theme|problem]
---

Show the person what happened on this Mac recently.

1. Run `summon status` and `summon events --limit 20` (add `--kind $ARGUMENTS` when an argument was given).
2. Summarize in a few lines: whether an agent is running, the latest settings changes (with their snapshot
   ids), the latest checkpoint, and any crashes or warnings.
3. If they want something undone, offer the exact command (`macctl undo <snapshot id>` for one change,
   `summon checkpoint undo <id>` for a whole session, `summon undo-session` for the latest) and run it only after they say yes.
4. Mention that the Summon menu bar app shows the same timeline under Activity… (`open summon://activity`).
