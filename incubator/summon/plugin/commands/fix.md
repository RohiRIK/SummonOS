---
description: Investigate and fix something wrong with this Mac
argument-hint: <what is wrong>
---

Something is wrong on this Mac: $ARGUMENTS

1. Gather facts first: `summon debug --print --since 1h`, then the `mac-logs` skill for the area involved
   (and `diagnose-crash-mac` if anything crashed).
2. Say what you found, separating evidence from inference.
3. Fix it if the fix is clear and reversible (Summon checkpointed this session; prefer `macctl` for settings).
   Ask first for anything outside the checkpoint (deleting user files, uninstalling apps, system files).
4. Verify the fix the same way you found the problem, then report what changed and how to undo it.
