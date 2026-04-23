#!/usr/bin/env bash
# change-tracker: PostToolUse hook
# Implements V1 (Semantic Diff Compression).
# Classifies, hashes, and clusters every file change.
# Fires on Write/Edit/MultiEdit.
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
# shellcheck source=../../../../shared/compat.sh
source "${SHARED_DIR}/compat.sh"

# ── Read hook input from stdin (capped at 1MB) ──
HOOK_INPUT=$(raven_read_stdin 1048576)

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
SESSION_HASH=$(raven_md5_file "${HOOK_TRANSCRIPT_PATH}" || echo "fallback-$$")

# ── Session cache file ──
CACHE_FILE="${RAVEN_CACHE_PREFIX}changes-${SESSION_HASH}.jsonl"
touch "$CACHE_FILE" 2>/dev/null || exit 0

# ── Compute current file hash ──
FILE_HASH=""
if [[ -f "$FILE_PATH" ]]; then
  FILE_HASH=$(raven_sha256_file "$FILE_PATH" || true)
fi

if [[ -z "$FILE_HASH" ]]; then
  exit 0
fi

# ── Look up previous hash for same file ──
PREV_HASH=""
if [[ -f "$CACHE_FILE" ]]; then
  PREV_HASH=$(grep -F "\"file\":\"${FILE_PATH}\"" "$CACHE_FILE" 2>/dev/null \
    | tail -1 \
    | jq -r '.hash // empty' 2>/dev/null || true)
fi

# ── Determine if file actually changed ──
CHANGED="true"
if [[ -n "$PREV_HASH" ]] && [[ "$FILE_HASH" == "$PREV_HASH" ]]; then
  CHANGED="false"
fi

# ── V1: Classify change type by file extension/path ──
CHANGE_TYPE="source_code"
BASENAME=$(basename "$FILE_PATH" 2>/dev/null || true)
EXTENSION="${BASENAME##*.}"
DIR_PATH=$(dirname "$FILE_PATH" 2>/dev/null || true)

# Config files
case "$BASENAME" in
  .env|.env.*|*.ini|*.cfg|*.conf)
    CHANGE_TYPE="config_change" ;;
esac
case "$EXTENSION" in
  json|yaml|yml|toml)
    CHANGE_TYPE="config_change" ;;
esac

# Dependency files (override config for known package manifests)
case "$BASENAME" in
  package.json|package-lock.json|yarn.lock|pnpm-lock.yaml)
    CHANGE_TYPE="dependency_change" ;;
  Cargo.toml|Cargo.lock|go.mod|go.sum)
    CHANGE_TYPE="dependency_change" ;;
  requirements.txt|Pipfile|Pipfile.lock|poetry.lock|pyproject.toml)
    CHANGE_TYPE="dependency_change" ;;
  Gemfile|Gemfile.lock|composer.json|composer.lock)
    CHANGE_TYPE="dependency_change" ;;
esac

# Test files
if printf "%s" "$FILE_PATH" | grep -qiE '(test|spec|__tests__)'; then
  CHANGE_TYPE="test_change"
fi

# Documentation
case "$EXTENSION" in
  md|txt|rst|adoc|doc)
    CHANGE_TYPE="documentation" ;;
esac

# Schema/migration files
case "$EXTENSION" in
  sql|prisma)
    CHANGE_TYPE="schema_change" ;;
esac
if printf "%s" "$DIR_PATH" | grep -qiE '(migration|migrate)'; then
  CHANGE_TYPE="schema_change"
fi

# ── Determine turn number ──
TURN=$(wc -l < "$CACHE_FILE" 2>/dev/null | tr -d '[:space:]')
TURN=${TURN:-0}
TURN=$((TURN + 1))

# ── Cluster: check co-location with recent changes ──
CLUSTER_ID=""
if [[ -f "$CACHE_FILE" ]]; then
  RECENT_DIR=$(tail -3 "$CACHE_FILE" 2>/dev/null \
    | jq -r '.file // empty' 2>/dev/null \
    | xargs -I{} dirname {} 2>/dev/null \
    | grep -F "$DIR_PATH" 2>/dev/null \
    | head -1 || true)
  if [[ -n "$RECENT_DIR" ]]; then
    # Same directory as a recent change — assign cluster
    CLUSTER_ID=$(printf "%s" "$DIR_PATH" | md5sum 2>/dev/null | cut -c1-8 || true)
  fi
fi

# ── Build change entry ──
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

CHANGE_ENTRY=$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg file "$FILE_PATH" \
  --arg hash "$FILE_HASH" \
  --arg prev_hash "$PREV_HASH" \
  --arg type "$CHANGE_TYPE" \
  --argjson changed "$CHANGED" \
  --arg cluster_id "$CLUSTER_ID" \
  --arg tool "$TOOL_NAME" \
  --argjson turn "$TURN" \
  '{ts:$ts, file:$file, hash:$hash, prev_hash:$prev_hash, type:$type, changed:$changed, cluster_id:$cluster_id, tool:$tool, turn:$turn}')

# ── Append to session cache ──
printf "%s\n" "$CHANGE_ENTRY" >> "$CACHE_FILE"

# ── Append to persistent state ──
STATE_DIR="${PLUGIN_ROOT}/state"
log_metric "${STATE_DIR}/changes.jsonl" "$CHANGE_ENTRY"

# ── Log metric ──
METRIC=$(jq -cn \
  --arg event "change_tracked" \
  --arg ts "$TIMESTAMP" \
  --arg file "$FILE_PATH" \
  --arg type "$CHANGE_TYPE" \
  --argjson turn "$TURN" \
  '{event:$event, ts:$ts, file:$file, type:$type, turn:$turn}')

log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"

exit 0
