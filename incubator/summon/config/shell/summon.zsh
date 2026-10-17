# Summon shell integration. /summon:setup adds `source <summon path>/config/shell/summon.zsh` to ~/.zshrc.

# `a` summons the default agent right here, in this terminal.
alias a='summon agent --inline'
# Straight into a task: ap "why is my disk full?"
ap() { summon agent prompt "$*"; }

# Agents by name, in their auto modes (same flags as Omarchy's cx / cy).
alias cx='claude --permission-mode auto'
alias cy='codex --approve-for-me'

# Quick helpers
alias theme='summon theme set'
alias themes='summon theme list'
alias mdebug='summon debug --print --since 1h'
