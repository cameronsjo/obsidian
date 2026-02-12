#!/usr/bin/env bash
# PreToolUse: Guard against permanent file deletion in Obsidian vaults.
# Blocks rm commands and instructs Claude to move files to .trash/ instead.
#
# Requires OBSIDIAN_VAULT env var. No env var = no protection.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# --- Gate ---
echo "$COMMAND" | grep -qE '\brm\b' || exit 0
[[ -n "${OBSIDIAN_VAULT:-}" ]] || exit 0

# --- Check: is rm targeting something inside the vault? ---
CWD=$(echo "$INPUT" | jq -r '.cwd // "/"')
PATHS=$(echo "$COMMAND" | grep -oE '/[^ "]+' 2>/dev/null || true)

IN_VAULT=false
for p in "$CWD" $PATHS; do
  [[ "$p" == "$OBSIDIAN_VAULT"* ]] && IN_VAULT=true && break
done

$IN_VAULT || exit 0

# --- Block and redirect to .trash/ ---
cat << EOF
{
  "decision": "block",
  "reason": "Obsidian vault detected. Do not use rm to delete vault files.\n\n.trash/ is Obsidian's built-in recycle bin. Move files there instead:\n  mkdir -p $OBSIDIAN_VAULT/.trash && mv <file> $OBSIDIAN_VAULT/.trash/\n\nThis preserves recoverability within Obsidian."
}
EOF
