# Summon shell integration. /summon:setup adds `source <summon path>/config/shell/summon.zsh` to ~/.zshrc.

# `a` summons the default agent right here, in this terminal.
alias a='summon agent --inline'
# Straight into a task: ap "why is my disk full?"
ap() { summon agent prompt "$*"; }

# Agents by name, with permission prompts bypassed (same flags Summon launches with).
alias cx='claude --dangerously-skip-permissions'
alias cy='codex --dangerously-bypass-approvals-and-sandbox'

# Quick helpers
alias theme='summon theme set'
alias themes='summon theme list'
alias mdebug='summon debug --print --since 1h'
