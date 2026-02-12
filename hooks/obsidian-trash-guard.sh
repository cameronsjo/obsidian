#!/usr/bin/env bash
# PreToolUse: Guard against permanent file deletion in Obsidian vaults.
# Blocks rm commands and instructs Claude to move files to .trash/ instead.
#
# Obsidian's .trash/ is its built-in recycle bin. Files deleted inside
# Obsidian go there — rm bypasses that and permanently destroys them.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Only intercept commands containing rm
if ! echo "$COMMAND" | grep -qE '\brm\b'; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // "/"')

# Fast path: if OBSIDIAN_VAULT is set, check paths against it directly
# before falling back to the directory walk.
check_under_vault() {
  local path="$1"
  local vault="$2"
  [[ "$path" == "$vault"* ]]
}

if [[ -n "${OBSIDIAN_VAULT:-}" && -d "$OBSIDIAN_VAULT" ]]; then
  VAULT_ROOT=""

  # Check CWD
  if check_under_vault "$CWD" "$OBSIDIAN_VAULT"; then
    VAULT_ROOT="$OBSIDIAN_VAULT"
  fi

  # Check absolute paths in the command
  if [[ -z "$VAULT_ROOT" ]]; then
    while IFS= read -r candidate; do
      if check_under_vault "$candidate" "$OBSIDIAN_VAULT"; then
        VAULT_ROOT="$OBSIDIAN_VAULT"
        break
      fi
    done < <(echo "$COMMAND" | grep -oE '/[^ "]+' 2>/dev/null || true)
  fi
else
  # Fallback: walk up from a directory looking for .obsidian/ (vault marker)
  find_vault_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
      if [[ -d "$dir/.obsidian" ]]; then
        echo "$dir"
        return 0
      fi
      dir=$(dirname "$dir")
    done
    return 1
  }

  # Check if CWD is inside a vault
  VAULT_ROOT=$(find_vault_root "$CWD" 2>/dev/null) || VAULT_ROOT=""

  # If CWD isn't in a vault, check absolute paths in the command
  if [[ -z "$VAULT_ROOT" ]]; then
    while IFS= read -r candidate; do
      dir=$(dirname "$candidate" 2>/dev/null) || continue
      VAULT_ROOT=$(find_vault_root "$dir" 2>/dev/null) || continue
      if [[ -n "$VAULT_ROOT" ]]; then
        break
      fi
    done < <(echo "$COMMAND" | grep -oE '/[^ "]+' 2>/dev/null || true)
  fi
fi

# Not in a vault — approve
if [[ -z "$VAULT_ROOT" ]]; then
  exit 0
fi

# In a vault — block the rm and instruct to use .trash/
TRASH_DIR="$VAULT_ROOT/.trash"
cat << EOF
{
  "decision": "block",
  "reason": "Obsidian vault detected. Do not use rm to delete vault files.\n\n.trash/ is Obsidian's built-in recycle bin. Move files there instead:\n  mkdir -p $TRASH_DIR && mv <file> $TRASH_DIR/\n\nThis preserves recoverability within Obsidian."
}
EOF
exit 0
