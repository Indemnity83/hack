#!/usr/bin/env zsh
set -euo pipefail

# hack — lightweight git helper with OpenAI
#
# Subcommands (interactive):
#   hack idea [-i "my idea"]
#   hack commit
#   hack propose
#   hack port [commit-sha] [target-branch]  (defaults to current branch)
#   hack done
#   hack prune
#
# Dependencies:
#   git, curl, jq
#   propose/done/prune: gh (GitHub CLI)
#   optional: git town, fzf (better UI for selections)

# ---- CONFIG ----
# Load API key from environment or config file
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hack/config"

# Source config file if it exists (allows it to set defaults)
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Set model default
: "${OPENAI_MODEL:=gpt-5.2}"

# Hard safety limits so we don't accidentally ship massive diffs:
MAX_CHARS_DIFF_COMMIT=20000
MAX_CHARS_DIFF_PROPOSE=50000
