#!/usr/bin/env bash
# trust-scorer: PostToolUse hook
# Implements V2 (Bayesian Trust Scoring).
# Computes Beta-Bernoulli posterior trust for each file change.
# Fires on Write/Edit/MultiEdit, after change-tracker.
# MUST exit 0 always.

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

# ── Read hook input from stdin ──
HOOK_INPUT=$(cat)

if ! validate_json "$HOOK_INPUT"; then
  exit 0
fi

TOOL_NAME=$(printf "%s" "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(printf "%s" "$HOOK_INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
HOOK_TRANSCRIPT_PATH=$(printf "%s" "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -z "$TOOL_NAME" ]]; then
  exit 0
fi

# ── Extract file path ──
FILE_PATH=$(printf "%s" "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# ── Sanitize path ──
DECODED=$(printf "%s" "$FILE_PATH" | sed -e 's/%2[eE]/./g' -e 's/%2[fF]/\//g' -e 's/%25/%/g')
if [[ "$DECODED" == *".."* ]]; then exit 0; fi

# ── Session hash ──
SESSION_HASH=$(md5sum "${HOOK_TRANSCRIPT_PATH}" 2>/dev/null | cut -c1-8 || echo "fallback-$$")

# ── Read latest change entry from change-tracker session cache ──
CHANGES_CACHE="${VIGIL_CACHE_PREFIX}changes-${SESSION_HASH}.jsonl"
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
TRUST_FILE="${STATE_DIR}/${VIGIL_TRUST_FILE##*/}"
TRUST_TMP="${TRUST_FILE}.tmp"
TRUST_LOCK="${TRUST_FILE}${VIGIL_LOCK_SUFFIX}"

# ── Read existing trust (or initialize) ──
TRUST_DATA="{}"
if [[ -f "$TRUST_FILE" ]]; then
  if jq empty "$TRUST_FILE" >/dev/null 2>&1; then
    TRUST_DATA=$(cat "$TRUST_FILE")
  fi
fi

# ── Read per-file prior (or use Beta(2,2) default) ──
# Use jq -n to safely construct the key lookup
FILE_KEY=$(printf "%s" "$FILE_PATH" | jq -Rr @json 2>/dev/null)
PRIOR_ALPHA=$(printf "%s" "$TRUST_DATA" | jq -r ".[${FILE_KEY}].alpha // ${VIGIL_PRIOR_ALPHA}" 2>/dev/null)
PRIOR_BETA=$(printf "%s" "$TRUST_DATA" | jq -r ".[${FILE_KEY}].beta // ${VIGIL_PRIOR_BETA}" 2>/dev/null)

# Ensure numeric
PRIOR_ALPHA=$(printf "%s" "$PRIOR_ALPHA" | grep -oE '[0-9]+\.?[0-9]*' || echo "$VIGIL_PRIOR_ALPHA")
PRIOR_BETA=$(printf "%s" "$PRIOR_BETA" | grep -oE '[0-9]+\.?[0-9]*' || echo "$VIGIL_PRIOR_BETA")

# ── V2: Compute base likelihood from change type ──
LIKELIHOOD="$VIGIL_LIKELIHOOD_SOURCE_SMALL"

case "$CHANGE_TYPE" in
  documentation)
    LIKELIHOOD="$VIGIL_LIKELIHOOD_DOCUMENTATION" ;;
  test_change)
    LIKELIHOOD="$VIGIL_LIKELIHOOD_TEST" ;;
  source_code)
    LIKELIHOOD="$VIGIL_LIKELIHOOD_SOURCE_SMALL" ;;
  schema_change)
    LIKELIHOOD="$VIGIL_LIKELIHOOD_SCHEMA" ;;
  dependency_change)
    LIKELIHOOD="$VIGIL_LIKELIHOOD_DEPENDENCY" ;;
  config_change)
    BASENAME=$(basename "$FILE_PATH" 2>/dev/null || true)
    case "$BASENAME" in
      .env|.env.*|*secret*|*credential*|*auth*)
        LIKELIHOOD="$VIGIL_LIKELIHOOD_CONFIG_SENSITIVE" ;;
      *)
        LIKELIHOOD="$VIGIL_LIKELIHOOD_CONFIG_NORMAL" ;;
    esac
    ;;
esac

# ── V2b: Content-based signal detection ──
# This is what distinguishes Vigil from a file-type classifier.
# Read the actual file and detect red-flag patterns.
RED_FLAGS=""

if [[ -f "$FILE_PATH" ]]; then
  FILE_CONTENT=$(head -500 "$FILE_PATH" 2>/dev/null || true)

  # Test files: detect weakened/gutted assertions
  if [[ "$CHANGE_TYPE" == "test_change" ]]; then
    # Trivial assertions: expect(true), expect(1).toBe(1), assert(true)
    TRIVIAL_COUNT=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'expect\(true\)|expect\(1\)\.toBe\(1\)|assert\(true\)|\.toBe\(true\)$' 2>/dev/null || echo "0")
    # Real assertions (anything with expect/assert that isn't trivial)
    REAL_ASSERTS=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'expect\(|assert[A-Z(]|\.toThrow|\.toEqual|\.toMatch|\.toContain|\.toBe\(' 2>/dev/null || echo "0")
    REAL_ASSERTS=$((REAL_ASSERTS - TRIVIAL_COUNT))
    REAL_ASSERTS=$((REAL_ASSERTS > 0 ? REAL_ASSERTS : 0))

    if [[ "$TRIVIAL_COUNT" -gt 0 ]] && [[ "$REAL_ASSERTS" -eq 0 ]]; then
      # ALL assertions are trivial — test is gutted
      LIKELIHOOD="0.1"
      RED_FLAGS="gutted_test"
    elif [[ "$TRIVIAL_COUNT" -gt 0 ]]; then
      # Mix of trivial and real — suspicious
      LIKELIHOOD=$(jq -n --argjson l "$LIKELIHOOD" '$l * 0.5' 2>/dev/null || echo "$LIKELIHOOD")
      RED_FLAGS="trivial_assertions"
    fi
  fi

  # Source code: detect removal of security controls
  if [[ "$CHANGE_TYPE" == "source_code" ]]; then
    # Check for absence of security patterns that were in the previous version
    # We detect this by checking if critical patterns are MISSING from current content
    HAS_RATE_LIMIT=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'rateLimit|rate.limit|throttle|rate_limit' 2>/dev/null || echo "0")
    HAS_AUTH=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'authenticate|authorize|requireAuth|isAuthenticated|verif(y|ied)' 2>/dev/null || echo "0")
    HAS_VALIDATION=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'validate|sanitize|escape|parameterize' 2>/dev/null || echo "0")

    # Check if the PREVIOUS version had these (via session cache)
    if [[ -f "$CHANGES_CACHE" ]]; then
      PREV_ENTRY=$(grep -F "\"file\":\"${FILE_PATH}\"" "$CHANGES_CACHE" 2>/dev/null | tail -2 | head -1 || true)
    fi

    # Detect algorithm downgrades
    HAS_WEAK_CRYPTO=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'HS256|MD5|SHA1[^0-9]|DES[^C]|ECB|eval\(' 2>/dev/null || echo "0")
    if [[ "$HAS_WEAK_CRYPTO" -gt 0 ]]; then
      LIKELIHOOD=$(jq -n --argjson l "$LIKELIHOOD" 'if $l > 0.3 then 0.3 else $l end' 2>/dev/null || echo "0.3")
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}weak_crypto"
    fi

    # Very short source file after edit = possibly gutted
    LINE_COUNT=$(printf "%s" "$FILE_CONTENT" | wc -l | tr -d '[:space:]')
    if [[ "$LINE_COUNT" -lt 5 ]] && [[ "$LINE_COUNT" -gt 0 ]]; then
      LIKELIHOOD=$(jq -n --argjson l "$LIKELIHOOD" '$l * 0.6' 2>/dev/null || echo "$LIKELIHOOD")
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}very_short_file"
    fi
  fi

  # Config files: detect dangerous patterns
  if [[ "$CHANGE_TYPE" == "config_change" ]]; then
    # Wildcard CORS
    HAS_WILDCARD_CORS=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'CORS.*=.*\*|cors.*:.*\*|"origin".*:.*"\*"' 2>/dev/null || echo "0")
    if [[ "$HAS_WILDCARD_CORS" -gt 0 ]]; then
      LIKELIHOOD=$(jq -n --argjson l "$LIKELIHOOD" 'if $l > 0.15 then 0.15 else $l end' 2>/dev/null || echo "0.15")
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}wildcard_cors"
    fi

    # Exposed secrets/keys
    HAS_SECRETS=$(printf "%s" "$FILE_CONTENT" | grep -ciE 'sk_live|sk-live|PRIVATE.KEY|secret_key|api.key.*=.*[a-zA-Z0-9]{20}' 2>/dev/null || echo "0")
    if [[ "$HAS_SECRETS" -gt 0 ]]; then
      LIKELIHOOD=$(jq -n --argjson l "$LIKELIHOOD" 'if $l > 0.1 then 0.1 else $l end' 2>/dev/null || echo "0.1")
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}exposed_secrets"
    fi

    # Debug mode in production configs
    HAS_DEBUG=$(printf "%s" "$FILE_CONTENT" | grep -ciE '"debug".*:.*true|DEBUG.*=.*true|debug.*=.*1' 2>/dev/null || echo "0")
    if [[ "$HAS_DEBUG" -gt 0 ]]; then
      LIKELIHOOD=$(jq -n --argjson l "$LIKELIHOOD" '$l * 0.7' 2>/dev/null || echo "$LIKELIHOOD")
      RED_FLAGS="${RED_FLAGS:+${RED_FLAGS},}debug_enabled"
    fi
  fi
fi

# ── Revert detection: penalize if hash matches a previous version ──
if [[ -n "$PREV_HASH" ]] && [[ -n "$CURRENT_HASH" ]] && [[ "$CURRENT_HASH" == "$PREV_HASH" ]]; then
  LIKELIHOOD=$(jq -n --argjson l "$LIKELIHOOD" '$l * 0.5' 2>/dev/null || echo "$LIKELIHOOD")
fi

# ── Posterior update: Beta-Bernoulli conjugate ──
NEW_ALPHA=$(jq -n --argjson a "$PRIOR_ALPHA" --argjson l "$LIKELIHOOD" '$a + $l' 2>/dev/null)
NEW_BETA=$(jq -n --argjson b "$PRIOR_BETA" --argjson l "$LIKELIHOOD" '$b + (1 - $l)' 2>/dev/null)
TRUST_SCORE=$(jq -n --argjson a "$NEW_ALPHA" --argjson b "$NEW_BETA" '$a / ($a + $b)' 2>/dev/null)

# Fallback if jq math fails
NEW_ALPHA=${NEW_ALPHA:-$PRIOR_ALPHA}
NEW_BETA=${NEW_BETA:-$PRIOR_BETA}
TRUST_SCORE=${TRUST_SCORE:-"0.5"}

# ── Write updated trust atomically ──
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

acquire_lock "$TRUST_LOCK" || exit 0

# Re-read trust file under lock (may have changed)
if [[ -f "$TRUST_FILE" ]] && jq empty "$TRUST_FILE" >/dev/null 2>&1; then
  TRUST_DATA=$(cat "$TRUST_FILE")
fi

TRUST_DATA=$(printf "%s" "$TRUST_DATA" | jq \
  --arg file "$FILE_PATH" \
  --argjson alpha "$NEW_ALPHA" \
  --argjson beta "$NEW_BETA" \
  --argjson score "$TRUST_SCORE" \
  --arg type "$CHANGE_TYPE" \
  --arg ts "$TIMESTAMP" \
  '.[$file] = {alpha: $alpha, beta: $beta, score: $score, type: $type, ts: $ts}' \
  2>/dev/null || echo "$TRUST_DATA")

# Prune: keep only most recent 200 files by timestamp
TRUST_DATA=$(printf "%s" "$TRUST_DATA" | jq '
  if (length > 200) then
    to_entries | sort_by(.value.ts) | reverse | .[0:200] | from_entries
  else . end
' 2>/dev/null || echo "$TRUST_DATA")

mkdir -p "$STATE_DIR"
printf "%s\n" "$TRUST_DATA" > "$TRUST_TMP"
mv "$TRUST_TMP" "$TRUST_FILE"

release_lock "$TRUST_LOCK"

# ── Write to session trust cache ──
TRUST_CACHE="${VIGIL_CACHE_PREFIX}trust-${SESSION_HASH}.jsonl"
TRUST_ENTRY=$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg file "$FILE_PATH" \
  --argjson score "$TRUST_SCORE" \
  --arg type "$CHANGE_TYPE" \
  --argjson alpha "$NEW_ALPHA" \
  --argjson beta "$NEW_BETA" \
  '{ts:$ts, file:$file, score:$score, type:$type, alpha:$alpha, beta:$beta}')
printf "%s\n" "$TRUST_ENTRY" >> "$TRUST_CACHE" 2>/dev/null || true

# ── Log metric ──
TURN=$(wc -l < "$TRUST_CACHE" 2>/dev/null | tr -d '[:space:]')
TURN=${TURN:-1}

METRIC=$(jq -cn \
  --arg event "trust_scored" \
  --arg ts "$TIMESTAMP" \
  --arg file "$FILE_PATH" \
  --argjson score "$TRUST_SCORE" \
  --arg type "$CHANGE_TYPE" \
  --argjson turn "$TURN" \
  '{event:$event, ts:$ts, file:$file, score:$score, type:$type, turn:$turn}')

log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"

# ── stderr output — ALWAYS show trust on every change ──
# This is the developer's primary feedback channel.
DISPLAY_SCORE=$(jq -n --argjson s "$TRUST_SCORE" '$s * 100 | floor / 100' 2>/dev/null || echo "$TRUST_SCORE")

# Short filename for display
SHORT_FILE=$(basename "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

IS_CRITICAL=$(jq -n --argjson s "$TRUST_SCORE" --argjson t "$VIGIL_TRUST_CRITICAL" 'if $s < $t then 1 else 0 end' 2>/dev/null || echo "0")
IS_LOW=$(jq -n --argjson s "$TRUST_SCORE" --argjson t "$VIGIL_TRUST_LOW" 'if $s < $t then 1 else 0 end' 2>/dev/null || echo "0")
IS_HIGH=$(jq -n --argjson s "$TRUST_SCORE" --argjson t "$VIGIL_TRUST_HIGH" 'if $s >= $t then 1 else 0 end' 2>/dev/null || echo "0")

# Build the flag suffix for display
FLAG_DISPLAY=""
if [[ -n "$RED_FLAGS" ]]; then
  # Translate flag codes to human-readable
  FLAG_DISPLAY=$(printf "%s" "$RED_FLAGS" | sed \
    -e 's/gutted_test/ALL ASSERTIONS DELETED/g' \
    -e 's/trivial_assertions/trivial assertions found/g' \
    -e 's/weak_crypto/weak crypto algorithm/g' \
    -e 's/very_short_file/file gutted/g' \
    -e 's/wildcard_cors/CORS=* in config/g' \
    -e 's/exposed_secrets/SECRETS IN PLAINTEXT/g' \
    -e 's/debug_enabled/debug mode on/g' \
    -e 's/,/ | /g')
fi

if [[ "$IS_CRITICAL" == "1" ]]; then
  printf "[Vigil] %s  trust: %s  CRITICAL — %s (%s)" \
    "$SHORT_FILE" "$DISPLAY_SCORE" "${FLAG_DISPLAY:-stop and review}" "$CHANGE_TYPE" >&2
elif [[ "$IS_LOW" == "1" ]]; then
  printf "[Vigil] %s  trust: %s  LOW — %s (%s)" \
    "$SHORT_FILE" "$DISPLAY_SCORE" "${FLAG_DISPLAY:-review recommended}" "$CHANGE_TYPE" >&2
elif [[ -n "$RED_FLAGS" ]]; then
  printf "[Vigil] %s  trust: %s  WARNING — %s (%s)" \
    "$SHORT_FILE" "$DISPLAY_SCORE" "$FLAG_DISPLAY" "$CHANGE_TYPE" >&2
else
  printf "[Vigil] %s  trust: %s (%s)" \
    "$SHORT_FILE" "$DISPLAY_SCORE" "$CHANGE_TYPE" >&2
fi

exit 0
