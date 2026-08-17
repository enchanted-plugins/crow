#!/usr/bin/env bash
# Test: save-session.sh handles gracefully when no sibling state exists
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/session-memory/hooks/pre-compact/save-session.sh"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SM_STATE="${REPO_ROOT}/plugins/session-memory/state"

# Clean ALL sibling state to simulate empty session
SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -f "${SM_STATE}/session-graph.json"
rm -rf "${SM_STATE}/session-graph.json.lock"
rm -f "${SM_STATE}/session-summary.md"
rm -f "${SM_STATE}/metrics.jsonl"
rm -rf "${SM_STATE}/metrics.jsonl.lock"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", hook_event_name: "PreCompact"}')

# Run the hook — should exit 0 even with no data
EXIT_CODE=0
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/session-memory" bash "$HOOK" 2>/dev/null || EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "FAIL: Hook should exit 0 even with no sibling data, got $EXIT_CODE"
  rm -f "$MOCK_TRANSCRIPT"
  exit 1
fi

# Verify a session-graph.json was still created (with empty data)
if [[ -f "${SM_STATE}/session-graph.json" ]]; then
  TOTAL=$(jq -r '.total_changes // 0' "${SM_STATE}/session-graph.json" 2>/dev/null)
  if [[ "$TOTAL" != "0" ]]; then
    echo "FAIL: Empty session should have 0 total_changes, got $TOTAL"
    rm -f "$MOCK_TRANSCRIPT"
    exit 1
  fi
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "${SM_STATE}/session-graph.json"
rm -rf "${SM_STATE}/session-graph.json.lock"
rm -f "${SM_STATE}/session-summary.md"
rm -f "${SM_STATE}/metrics.jsonl"
rm -rf "${SM_STATE}/metrics.jsonl.lock"

exit 0
