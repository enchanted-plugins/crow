#!/usr/bin/env bash
# decision-gate: PostToolUse hook
# Implements V5 (Adversarial Self-Review).
# Advisory gating — exit 0 + stderr, NOT exit 2 blocking.
# Fires on Write/Edit/MultiEdit AFTER the write occurs, reading the flags that
# trust-scorer's detector suite recorded for this change (same PostToolUse event).
# MUST exit 0 always.


# Subagent recursion guard — see shared/conduct/hooks.md
if [[ -n "${CLAUDE_SUBAGENT:-}" ]]; then exit 0; fi

trap 'exit 0' ERR INT TERM

set -uo pipefail

# ── Check jq availability ──
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Resolve paths
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SHARED_DIR="${PLUGIN_ROOT}/../../shared"

# shellcheck source=../../../../shared/constants.sh
source "${SHARED_DIR}/constants.sh"
# shellcheck source=../../../../shared/sanitize.sh
source "${SHARED_DIR}/sanitize.sh"
# shellcheck source=../../../../shared/metrics.sh
source "${SHARED_DIR}/metrics.sh"
# shellcheck source=../../../../shared/compat.sh
source "${SHARED_DIR}/compat.sh"

# ── Read hook input from stdin (capped at 1MB) ──
HOOK_INPUT=$(crow_read_stdin 1048576)

if ! validate_json "$HOOK_INPUT"; then
  exit 0
fi

# Extract all fields in a single jq call
PARSED=$(printf "%s" "$HOOK_INPUT" | jq -r '[.tool_input.file_path // "", .transcript_path // ""] | join("\t")' 2>/dev/null)
FILE_PATH=$(printf "%s" "$PARSED" | cut -f1)
HOOK_TRANSCRIPT_PATH=$(printf "%s" "$PARSED" | cut -f2)

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# ── Sanitize path ──
DECODED=$(printf "%s" "$FILE_PATH" | sed -e 's/%2[eE]/./g' -e 's/%2[fF]/\//g' -e 's/%25/%/g')
if [[ "$DECODED" == *".."* ]]; then exit 0; fi

# ── Session hash ──
SESSION_HASH=$(crow_md5_file "${HOOK_TRANSCRIPT_PATH}" || echo "fallback-$$")

# ── Cooldown check ──
COOLDOWN_FILE="${CROW_CACHE_PREFIX}gate-cooldown-${SESSION_HASH}"

# Determine current turn from changes cache
CHANGES_CACHE="${CROW_CACHE_PREFIX}changes-${SESSION_HASH}.jsonl"
CURRENT_TURN=0
if [[ -f "$CHANGES_CACHE" ]]; then
  CURRENT_TURN=$(wc -l < "$CHANGES_CACHE" 2>/dev/null | tr -d '[:space:]')
fi
CURRENT_TURN=$((CURRENT_TURN + 1))

LAST_ADVISORY_TURN=0
if [[ -f "$COOLDOWN_FILE" ]]; then
  LAST_ADVISORY_TURN=$(cat "$COOLDOWN_FILE" 2>/dev/null | tr -d '[:space:]')
  LAST_ADVISORY_TURN=${LAST_ADVISORY_TURN:-0}
fi

if [[ "$LAST_ADVISORY_TURN" -gt 0 ]] && [[ $((CURRENT_TURN - LAST_ADVISORY_TURN)) -lt "$CROW_REVIEW_COOLDOWN_TURNS" ]]; then
  exit 0
fi

# ── Read the detector flags for this file (from trust-scorer's session cache) ──
FLAGS_CACHE="${CROW_CACHE_PREFIX}flags-${SESSION_HASH}.jsonl"
SEVERITY="clean"
CHANGE_TYPE="source_code"
FLAGS_JSON="[]"

if [[ -f "$FLAGS_CACHE" ]]; then
  LATEST=$(grep -F "\"file\":\"${FILE_PATH}\"" "$FLAGS_CACHE" 2>/dev/null | tail -1 || true)
  if [[ -n "$LATEST" ]]; then
    SEVERITY=$(printf "%s" "$LATEST" | jq -r '.severity // "clean"' 2>/dev/null)
    CHANGE_TYPE=$(printf "%s" "$LATEST" | jq -r '.type // "source_code"' 2>/dev/null)
    FLAGS_JSON=$(printf "%s" "$LATEST" | jq -c '.flags // []' 2>/dev/null || echo "[]")
  fi
fi

# ── No flags → nothing to surface for review ──
if [[ "$SEVERITY" == "clean" ]]; then
  exit 0
fi

# ── V5: Adversarial Self-Review — type-specific questions for flagged changes ──
case "$CHANGE_TYPE" in
  config_change)
    QUESTIONS="Does this config change expose secrets or API keys? Does it break environment-specific overrides?" ;;
  source_code)
    QUESTIONS="Does this change break existing tests? Does it introduce a regression in critical paths?" ;;
  test_change)
    QUESTIONS="Does this weaken test assertions? Does it test implementation details instead of behavior?" ;;
  schema_change)
    QUESTIONS="Is this migration reversible? Does it break existing data or downstream consumers?" ;;
  dependency_change)
    QUESTIONS="Has this dependency been audited? Does this version bump break peer dependencies?" ;;
  documentation)
    QUESTIONS="Does this documentation accurately reflect the current implementation?" ;;
  *)
    QUESTIONS="What is the intent of this change? Does it align with the current task?" ;;
esac

# ── Write adversary context fixture (avoid re-extraction in adversary agent) ──
STATE_DIR="${PLUGIN_ROOT}/state"
mkdir -p "$STATE_DIR"
DIFF_CONTENT=$(printf "%s" "$HOOK_INPUT" | jq -r '.tool_input.new_string // .tool_input.content // ""' 2>/dev/null || echo "")
ADVERSARY_CTX=$(jq -cn \
  --arg file "$FILE_PATH" \
  --arg diff "$DIFF_CONTENT" \
  --arg severity "$SEVERITY" \
  --argjson flags "$FLAGS_JSON" \
  --arg change_type "$CHANGE_TYPE" \
  '{file: $file, diff: $diff, severity: $severity, flags: $flags, change_type: $change_type}')
printf "%s\n" "$ADVERSARY_CTX" > "${STATE_DIR}/adversary-context.json" 2>/dev/null || true

# ── Construct stderr advisory ──
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SHORT_FILE=$(basename "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
FLAG_DISPLAY=$(printf "%s" "$FLAGS_JSON" | jq -r 'join(", ")' 2>/dev/null || echo "")

printf "[Crow] REVIEW BEFORE CONTINUING: %s  %s — %s (%s)\n  Ask yourself: %s" \
  "$SHORT_FILE" "$SEVERITY" "${FLAG_DISPLAY:-flagged}" "$CHANGE_TYPE" "$QUESTIONS" >&2

# ── Update cooldown ──
printf "%s" "$CURRENT_TURN" > "$COOLDOWN_FILE" 2>/dev/null || true

# ── Log metric ──
METRIC=$(jq -cn \
  --arg event "review_advisory" \
  --arg ts "$TIMESTAMP" \
  --arg file "$FILE_PATH" \
  --arg severity "$SEVERITY" \
  --argjson flags "$FLAGS_JSON" \
  --arg type "$CHANGE_TYPE" \
  --argjson turn "$CURRENT_TURN" \
  '{event:$event, ts:$ts, file:$file, severity:$severity, flags:$flags, type:$type, turn:$turn}')

log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"

exit 0
