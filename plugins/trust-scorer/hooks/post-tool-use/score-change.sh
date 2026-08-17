#!/usr/bin/env bash
# trust-scorer: PostToolUse hook
# Content-detector suite (V2b). Assesses each file change STATELESSLY by its own
# content — no Bayesian posterior, no cross-session accumulation, no trust score.
# Runs a set of red-flag detectors, derives a SEVERITY, and emits an advisory.
# Fires on Write/Edit/MultiEdit, after change-tracker.
# MUST exit 0 always (advisory detector; never blocks).


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
PARSED=$(printf "%s" "$HOOK_INPUT" | jq -r '[.tool_name // "", .tool_input.file_path // "", .transcript_path // ""] | join("\t")' 2>/dev/null)
TOOL_NAME=$(printf "%s" "$PARSED" | cut -f1)
FILE_PATH=$(printf "%s" "$PARSED" | cut -f2)
HOOK_TRANSCRIPT_PATH=$(printf "%s" "$PARSED" | cut -f3)

if [[ -z "$TOOL_NAME" ]] || [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# ── Sanitize path ──
DECODED=$(printf "%s" "$FILE_PATH" | sed -e 's/%2[eE]/./g' -e 's/%2[fF]/\//g' -e 's/%25/%/g')
if [[ "$DECODED" == *".."* ]]; then exit 0; fi

# ── Session hash ──
SESSION_HASH=$(crow_md5_file "${HOOK_TRANSCRIPT_PATH}" || echo "fallback-$$")

# ── Read latest change entry from change-tracker session cache ──
# Yields the change type and the current/previous content hashes for this file.
CHANGES_CACHE="${CROW_CACHE_PREFIX}changes-${SESSION_HASH}.jsonl"
CHANGE_TYPE="source_code"
PREV_HASH=""
CURRENT_HASH=""

if [[ -f "$CHANGES_CACHE" ]]; then
  LATEST=$(grep -F "\"file\":\"${FILE_PATH}\"" "$CHANGES_CACHE" 2>/dev/null | tail -1 || true)
  if [[ -n "$LATEST" ]]; then
    CHANGE_TYPE=$(printf "%s" "$LATEST" | jq -r '.type // "source_code"' 2>/dev/null)
    PREV_HASH=$(printf "%s" "$LATEST" | jq -r '.prev_hash // empty' 2>/dev/null)
    CURRENT_HASH=$(printf "%s" "$LATEST" | jq -r '.hash // empty' 2>/dev/null)
  fi
fi

# ── State directory ──
STATE_DIR="${PLUGIN_ROOT}/state"

# ── V2b: Content-based red-flag detection ──
# This IS Crow's trust signal: honest, content-derived flags — not a file-type
# constant dressed up as a probability. Read the actual file and detect
# red-flag patterns. Skip binary files — they produce false positives.
# Each detector ONLY appends a flag code to RED_FLAGS; SEVERITY is derived below.
RED_FLAGS=""

if [[ -f "$FILE_PATH" ]] && ! crow_is_binary "$FILE_PATH"; then
  FILE_CONTENT=$(head -500 "$FILE_PATH" 2>/dev/null || true)

  # Test files: detect weakened/gutted assertions
  if [[ "$CHANGE_TYPE" == "test_change" ]]; then
    # Trivial assertions: expect(true), expect(1).toBe(1), assert(true)
    TRIVIAL_COUNT=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'expect\(true\)|expect\(1\)\.toBe\(1\)|assert\(true\)|\.toBe\(true\)$' 2>/dev/null || true)
    # Real assertions (anything with expect/assert that isn't trivial)
    REAL_ASSERTS=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'expect\(|assert[A-Z(]|\.toThrow|\.toEqual|\.toMatch|\.toContain|\.toBe\(' 2>/dev/null || true)
    REAL_ASSERTS=$((REAL_ASSERTS - TRIVIAL_COUNT))
    REAL_ASSERTS=$((REAL_ASSERTS > 0 ? REAL_ASSERTS : 0))

    if [[ "$TRIVIAL_COUNT" -gt 0 ]] && [[ "$REAL_ASSERTS" -eq 0 ]]; then
      # ALL assertions are trivial — test is gutted
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}gutted_test"
    elif [[ "$TRIVIAL_COUNT" -gt 0 ]]; then
      # Mix of trivial and real — suspicious
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}trivial_assertions"
    fi
  fi

  # Source code: detect removal of security controls / downgrades
  if [[ "$CHANGE_TYPE" == "source_code" ]]; then
    # Detect algorithm downgrades (only in code, not comments)
    # Strip single-line comments before matching to reduce false positives
    CODE_ONLY=$(printf "%s" "$FILE_CONTENT" | sed -E 's|(//.*$)||; s|(#.*$)||' 2>/dev/null || echo "$FILE_CONTENT")
    HAS_WEAK_CRYPTO=$(printf "%s" "$CODE_ONLY" | grep -ciE '"HS256"|'\''HS256'\''|algorithms.*HS256|md5\(|MD5\(|eval\(' 2>/dev/null || true)
    if [[ "$HAS_WEAK_CRYPTO" -gt 0 ]]; then
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}weak_crypto"
    fi

    # Very short source file after edit = possibly gutted
    LINE_COUNT=$(printf "%s" "$FILE_CONTENT" | wc -l | tr -d '[:space:]')
    if [[ "$LINE_COUNT" -lt 5 ]] && [[ "$LINE_COUNT" -gt 0 ]]; then
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}very_short_file"
    fi
  fi

  # Config files: detect dangerous patterns
  if [[ "$CHANGE_TYPE" == "config_change" ]]; then
    # Wildcard CORS
    HAS_WILDCARD_CORS=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'CORS.*=.*\*|cors.*:.*\*|"origin".*:.*"\*"' 2>/dev/null || true)
    if [[ "$HAS_WILDCARD_CORS" -gt 0 ]]; then
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}wildcard_cors"
    fi

    # Exposed secrets/keys
    HAS_SECRETS=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'sk_live|sk-live|PRIVATE.KEY|secret_key|api.key.*=.*[a-zA-Z0-9]{20}' 2>/dev/null || true)
    if [[ "$HAS_SECRETS" -gt 0 ]]; then
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}exposed_secrets"
    fi

    # Debug mode in production configs
    HAS_DEBUG=$(printf "%s" "$FILE_CONTENT" | grep -ciE '"debug".*:.*true|DEBUG.*=.*true|debug.*=.*1' 2>/dev/null || true)
    if [[ "$HAS_DEBUG" -gt 0 ]]; then
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}debug_enabled"
    fi
  fi
fi

# ── Revert detection: flag if the new content hash matches a previous version ──
if [[ -n "$PREV_HASH" ]] && [[ -n "$CURRENT_HASH" ]] && [[ "$CURRENT_HASH" == "$PREV_HASH" ]]; then
  RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}reverted"
fi

# ── Derive SEVERITY from the flags that fired (max severity wins) ──
# CRITICAL: exposed_secrets, gutted_test
# HIGH:     weak_crypto, wildcard_cors
# WARNING:  trivial_assertions, very_short_file, debug_enabled, reverted
# clean:    no flags
SEVERITY="clean"
case ",${RED_FLAGS}," in
  *,exposed_secrets,*|*,gutted_test,*)
    SEVERITY="CRITICAL" ;;
  *,weak_crypto,*|*,wildcard_cors,*)
    SEVERITY="HIGH" ;;
  *,trivial_assertions,*|*,very_short_file,*|*,debug_enabled,*|*,reverted,*)
    SEVERITY="WARNING" ;;
esac

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Build the flags JSON array ──
if [[ -n "$RED_FLAGS" ]]; then
  FLAGS_JSON=$(printf "%s" "$RED_FLAGS" | jq -Rc 'split(",")' 2>/dev/null || echo "[]")
else
  FLAGS_JSON="[]"
fi

# ── Write flag record to session cache (ephemeral, per-session — NOT persisted) ──
FLAGS_CACHE="${CROW_CACHE_PREFIX}flags-${SESSION_HASH}.jsonl"
FLAG_ENTRY=$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg file "$FILE_PATH" \
  --arg severity "$SEVERITY" \
  --argjson flags "$FLAGS_JSON" \
  --arg type "$CHANGE_TYPE" \
  '{ts:$ts, file:$file, severity:$severity, flags:$flags, type:$type}')
mkdir -p "$STATE_DIR"
printf "%s\n" "$FLAG_ENTRY" >> "$FLAGS_CACHE" 2>/dev/null || true

# ── Log metric ──
TURN=$(wc -l < "$FLAGS_CACHE" 2>/dev/null | tr -d '[:space:]')
TURN=${TURN:-1}

METRIC=$(jq -cn \
  --arg event "change_flagged" \
  --arg ts "$TIMESTAMP" \
  --arg file "$FILE_PATH" \
  --arg severity "$SEVERITY" \
  --argjson flags "$FLAGS_JSON" \
  --arg type "$CHANGE_TYPE" \
  --argjson turn "$TURN" \
  '{event:$event, ts:$ts, file:$file, severity:$severity, flags:$flags, type:$type, turn:$turn}')

log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"

# ── stderr output — advisory feedback channel ──
SHORT_FILE=$(basename "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

if [[ -n "$RED_FLAGS" ]]; then
  # Human-readable flag list
  FLAG_DISPLAY=$(printf "%s" "$RED_FLAGS" | sed \
    -e 's/gutted_test/ALL ASSERTIONS DELETED/g' \
    -e 's/trivial_assertions/trivial assertions found/g' \
    -e 's/weak_crypto/weak crypto algorithm/g' \
    -e 's/very_short_file/file gutted/g' \
    -e 's/wildcard_cors/CORS=* in config/g' \
    -e 's/exposed_secrets/SECRETS IN PLAINTEXT/g' \
    -e 's/debug_enabled/debug mode on/g' \
    -e 's/reverted/change reverted to prior version/g' \
    -e 's/,/ | /g')
  printf "[Crow] %s  %s — %s (%s)" \
    "$SHORT_FILE" "$SEVERITY" "$FLAG_DISPLAY" "$CHANGE_TYPE" >&2
else
  printf "[Crow] %s  clean (%s)" "$SHORT_FILE" "$CHANGE_TYPE" >&2
fi

exit 0
