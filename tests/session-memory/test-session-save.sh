#!/usr/bin/env bash
# Test: save-session.sh creates session-graph.json and session-summary.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/session-memory/hooks/pre-compact/save-session.sh"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"
SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")

# Set up test data in sibling plugins
CT_STATE="${REPO_ROOT}/plugins/change-tracker/state"
TS_STATE="${REPO_ROOT}/plugins/trust-scorer/state"
DG_STATE="${REPO_ROOT}/plugins/decision-gate/state"
SM_STATE="${REPO_ROOT}/plugins/session-memory/state"

mkdir -p "$CT_STATE" "$TS_STATE" "$DG_STATE" "$SM_STATE"

# Create sample changes
echo '{"ts":"2026-04-14T10:00:00Z","file":"src/app.ts","hash":"abc123","type":"source_code","changed":true,"cluster_id":"","tool":"Write","turn":1}' > "${CT_STATE}/changes.jsonl"
echo '{"ts":"2026-04-14T10:01:00Z","file":"src/db.ts","hash":"def456","type":"schema_change","changed":true,"cluster_id":"","tool":"Edit","turn":2}' >> "${CT_STATE}/changes.jsonl"

# Create sample detector flags (trust-scorer session cache, keyed by session hash)
FLAGS_CACHE="/tmp/crow-flags-${SESSION_HASH}.jsonl"
echo '{"ts":"2026-04-14T10:00:00Z","file":"src/app.ts","severity":"clean","flags":[],"type":"source_code"}' > "$FLAGS_CACHE"
echo '{"ts":"2026-04-14T10:01:00Z","file":"src/db.ts","severity":"WARNING","flags":["reverted"],"type":"schema_change"}' >> "$FLAGS_CACHE"

# Clean session-memory state
rm -f "${SM_STATE}/session-graph.json"
rm -rf "${SM_STATE}/session-graph.json.lock"
rm -f "${SM_STATE}/session-summary.md"
rm -f "${SM_STATE}/metrics.jsonl"
rm -rf "${SM_STATE}/metrics.jsonl.lock"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", hook_event_name: "PreCompact"}')

# Run the hook
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/session-memory" bash "$HOOK" 2>/dev/null

# Verify session-graph.json was created
if [[ ! -f "${SM_STATE}/session-graph.json" ]]; then
  echo "FAIL: session-graph.json not created"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify it's valid JSON
if ! jq empty "${SM_STATE}/session-graph.json" >/dev/null 2>&1; then
  echo "FAIL: session-graph.json is not valid JSON"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify session-summary.md was created
if [[ ! -f "${SM_STATE}/session-summary.md" ]]; then
  echo "FAIL: session-summary.md not created"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify summary contains severity overview (not the old trust score)
if ! grep -q "Severity Overview" "${SM_STATE}/session-summary.md"; then
  echo "FAIL: session-summary.md missing Severity Overview section"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify no numeric trust score leaked into the graph or summary
if grep -qiE '"score"|"alpha"|"beta"|Beta-Bernoulli' "${SM_STATE}/session-graph.json" "${SM_STATE}/session-summary.md"; then
  echo "FAIL: session state must not contain score/alpha/beta/Beta-Bernoulli"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${CT_STATE}/changes.jsonl"
rm -f "${SM_STATE}/session-graph.json"
rm -rf "${SM_STATE}/session-graph.json.lock"
rm -f "${SM_STATE}/session-summary.md"
rm -f "${SM_STATE}/metrics.jsonl"
rm -rf "${SM_STATE}/metrics.jsonl.lock"

exit 0
