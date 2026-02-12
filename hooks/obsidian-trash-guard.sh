#!/usr/bin/env bash
# PreToolUse: Guard against permanent file deletion in Obsidian vaults.
# Blocks rm commands and instructs Claude to move files to .trash/ instead.
#
# Obsidian's .trash/ is its built-in recycle bin. Files deleted inside
# Obsidian go there — rm bypasses that and permanently destroys them.
#
# Requires OBSIDIAN_VAULT env var for the fast path. Falls back to
# walking up directories looking for .obsidian/ if unset.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# --- Gate: should this hook even run? ---
echo "$COMMAND" | grep -qE '\brm\b' || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // "/"')
PATHS=$(echo "$COMMAND" | grep -oE '/[^ "]+' 2>/dev/null || true)

# --- Detect vault: easy mode (env var) or hard mode (dir walk) ---
VAULT_ROOT=""

if [[ -n "${OBSIDIAN_VAULT:-}" ]]; then
  # Easy: prefix match against known vault path
  for p in "$CWD" $PATHS; do
    [[ "$p" == "$OBSIDIAN_VAULT"* ]] && VAULT_ROOT="$OBSIDIAN_VAULT" && break
  done
else
  # Hard: walk up looking for .obsidian/
  for p in "$CWD" $PATHS; do
    dir=$(dirname "$p" 2>/dev/null) || continue
    while [[ "$dir" != "/" ]]; do
      if [[ -d "$dir/.obsidian" ]]; then
        VAULT_ROOT="$dir"
        break 2
      fi
      dir=$(dirname "$dir")
    done
  done
fi

[[ -z "$VAULT_ROOT" ]] && exit 0

# --- Block and redirect to .trash/ ---
TRASH_DIR="$VAULT_ROOT/.trash"
cat << EOF
{
  "decision": "block",
  "reason": "Obsidian vault detected. Do not use rm to delete vault files.\n\n.trash/ is Obsidian's built-in recycle bin. Move files there instead:\n  mkdir -p $TRASH_DIR && mv <file> $TRASH_DIR/\n\nThis preserves recoverability within Obsidian."
}
EOF
