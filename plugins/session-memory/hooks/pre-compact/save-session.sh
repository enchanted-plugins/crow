#!/usr/bin/env bash
# session-memory: PreCompact hook
# Implements V4 (Session Continuity Graph) and V6 (Gauss Learning).
# Saves session state before compaction wipes context.
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
PLUGINS_DIR="${PLUGIN_ROOT}/.."

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

HOOK_TRANSCRIPT_PATH=$(printf "%s" "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
HOOK_CWD=$(printf "%s" "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
HOOK_CWD="${HOOK_CWD:-$(pwd)}"

# ── Session hash ──
SESSION_HASH=$(md5sum "${HOOK_TRANSCRIPT_PATH}" 2>/dev/null | cut -c1-8 || echo "fallback-$$")

# ── State directories ──
STATE_DIR="${PLUGIN_ROOT}/state"
CT_CHANGES="${PLUGINS_DIR}/change-tracker/state/changes.jsonl"
TS_TRUST="${PLUGINS_DIR}/trust-scorer/state/trust.json"
DG_METRICS="${PLUGINS_DIR}/decision-gate/state/metrics.jsonl"

# ── Gather change data (bounded read) ──
CHANGES_DATA="[]"
if [[ -f "$CT_CHANGES" ]]; then
  CHANGES_DATA=$(tail -200 "$CT_CHANGES" 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")
fi

# ── Gather trust data ──
TRUST_DATA="{}"
if [[ -f "$TS_TRUST" ]] && jq empty "$TS_TRUST" >/dev/null 2>&1; then
  TRUST_DATA=$(cat "$TS_TRUST")
fi

# ── Gather review advisory data ──
REVIEW_COUNT=0
if [[ -f "$DG_METRICS" ]]; then
  REVIEW_COUNT=$(grep -c '"review_advisory"' "$DG_METRICS" 2>/dev/null || true)
  REVIEW_COUNT=$(echo "$REVIEW_COUNT" | tr -d '[:space:]')
fi
REVIEW_COUNT=${REVIEW_COUNT:-0}

# ── V4: Session Continuity Graph ──
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Count changes by type
TOTAL_CHANGES=$(printf "%s" "$CHANGES_DATA" | jq 'length' 2>/dev/null || echo "0")

# Build file nodes from changes
FILE_NODES=$(printf "%s" "$CHANGES_DATA" | jq '
  group_by(.file) |
  map({
    file: .[0].file,
    type: .[0].type,
    change_count: length,
    last_hash: .[-1].hash,
    cluster_id: .[0].cluster_id
  }) |
  sort_by(-.change_count) |
  .[0:50]
' 2>/dev/null || echo "[]")

# Count trust categories
TRUST_HIGH=$(printf "%s" "$TRUST_DATA" | jq --argjson t "$VIGIL_TRUST_HIGH" \
  '[to_entries[] | select(.value.score >= $t)] | length' 2>/dev/null || echo "0")
TRUST_LOW=$(printf "%s" "$TRUST_DATA" | jq --argjson t "$VIGIL_TRUST_LOW" \
  '[to_entries[] | select(.value.score < $t)] | length' 2>/dev/null || echo "0")
TRUST_CRITICAL=$(printf "%s" "$TRUST_DATA" | jq --argjson t "$VIGIL_TRUST_CRITICAL" \
  '[to_entries[] | select(.value.score < $t)] | length' 2>/dev/null || echo "0")

# Build edges from cluster relationships
EDGES=$(printf "%s" "$CHANGES_DATA" | jq '
  [.[] | select(.cluster_id != "")] |
  group_by(.cluster_id) |
  map(select(length > 1) | {
    cluster: .[0].cluster_id,
    files: [.[].file] | unique
  }) |
  .[0:20]
' 2>/dev/null || echo "[]")

# Build graph JSON
SESSION_GRAPH=$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg session "$SESSION_HASH" \
  --argjson nodes "$FILE_NODES" \
  --argjson edges "$EDGES" \
  --argjson total_changes "$TOTAL_CHANGES" \
  --argjson trust_high "$TRUST_HIGH" \
  --argjson trust_low "$TRUST_LOW" \
  --argjson trust_critical "$TRUST_CRITICAL" \
  --argjson reviews "$REVIEW_COUNT" \
  '{
    ts: $ts,
    session: $session,
    total_changes: $total_changes,
    trust: {high: $trust_high, low: $trust_low, critical: $trust_critical},
    reviews: $reviews,
    nodes: $nodes,
    edges: $edges
  }' 2>/dev/null)

if [[ -z "$SESSION_GRAPH" ]] || [[ "$SESSION_GRAPH" == "null" ]]; then
  SESSION_GRAPH='{"ts":"'"$TIMESTAMP"'","session":"'"$SESSION_HASH"'","total_changes":0,"trust":{"high":0,"low":0,"critical":0},"reviews":0,"nodes":[],"edges":[]}'
fi

# ── Build session summary markdown ──
# Top changes by trust (riskiest first)
TOP_RISKY=$(printf "%s" "$TRUST_DATA" | jq -r '
  to_entries |
  sort_by(.value.score) |
  .[0:10] |
  map("- \(.key) (trust: \(.value.score | tostring | .[0:4]), type: \(.value.type))") |
  join("\n")
' 2>/dev/null || echo "No trust data")

# Recent review advisories
RECENT_REVIEWS=""
if [[ -f "$DG_METRICS" ]]; then
  RECENT_REVIEWS=$(grep '"review_advisory"' "$DG_METRICS" 2>/dev/null \
    | tail -5 \
    | jq -r '"- \(.file) (trust: \(.score), IG: \(.ig))"' 2>/dev/null \
    | head -5 || true)
fi
RECENT_REVIEWS=${RECENT_REVIEWS:-"No review advisories issued"}

# Git info (graceful without git)
GIT_BRANCH=""
GIT_LOG=""
if command -v git >/dev/null 2>&1; then
  GIT_BRANCH=$(cd "$HOOK_CWD" && git branch --show-current 2>/dev/null || true)
  GIT_LOG=$(cd "$HOOK_CWD" && git log --oneline -5 2>/dev/null || true)
fi

SESSION_SUMMARY=$(cat <<SUMMARY
# Vigil Session Summary
> Saved at: ${TIMESTAMP}
> Session: ${SESSION_HASH}
> Branch: ${GIT_BRANCH:-N/A}

## Trust Overview
High trust: ${TRUST_HIGH} | Low trust: ${TRUST_LOW} | Critical: ${TRUST_CRITICAL}

## Key Changes (${TOTAL_CHANGES} total)
${TOP_RISKY}

## Review Decisions (${REVIEW_COUNT} advisories)
${RECENT_REVIEWS}

## Recent Commits
${GIT_LOG:-None}
SUMMARY
)

# ── Enforce 50KB limit ──
SUMMARY_BYTES=${#SESSION_SUMMARY}
if [[ "$SUMMARY_BYTES" -gt "$VIGIL_MAX_GRAPH_BYTES" ]]; then
  SESSION_SUMMARY="${SESSION_SUMMARY:0:$VIGIL_MAX_GRAPH_BYTES}

[truncated, summary exceeded ${VIGIL_MAX_GRAPH_BYTES} bytes]"
fi

# ── Write atomically with lock ──
GRAPH_FILE="${STATE_DIR}/${VIGIL_SESSION_GRAPH##*/}"
SUMMARY_FILE="${STATE_DIR}/${VIGIL_SESSION_SUMMARY##*/}"
GRAPH_TMP="${GRAPH_FILE}.tmp"
SUMMARY_TMP="${SUMMARY_FILE}.tmp"
LOCK_DIR="${GRAPH_FILE}${VIGIL_LOCK_SUFFIX}"

acquire_lock "$LOCK_DIR" || exit 0

mkdir -p "$STATE_DIR"
printf "%s\n" "$SESSION_GRAPH" > "$GRAPH_TMP"
mv "$GRAPH_TMP" "$GRAPH_FILE"

printf "%s" "$SESSION_SUMMARY" > "$SUMMARY_TMP"
mv "$SUMMARY_TMP" "$SUMMARY_FILE"

release_lock "$LOCK_DIR"

# ── V6: Gauss Learning (call Python if available) ──
LEARNINGS_SCRIPT="${SHARED_DIR}/scripts/learnings.py"
if command -v python3 >/dev/null 2>&1 && [[ -f "$LEARNINGS_SCRIPT" ]]; then
  python3 "$LEARNINGS_SCRIPT" "$PLUGINS_DIR" 2>/dev/null || true
fi

# ── Log metric ──
METRIC=$(jq -cn \
  --arg event "session_saved" \
  --arg ts "$TIMESTAMP" \
  --argjson total_changes "$TOTAL_CHANGES" \
  --argjson trust_low "$TRUST_LOW" \
  --argjson trust_critical "$TRUST_CRITICAL" \
  --argjson reviews "$REVIEW_COUNT" \
  '{event:$event, ts:$ts, total_changes:$total_changes, trust_low:$trust_low, trust_critical:$trust_critical, reviews:$reviews}')

log_metric "${STATE_DIR}/metrics.jsonl" "$METRIC"

exit 0
