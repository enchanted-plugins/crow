#!/usr/bin/env bash
# Test: gate-change.sh produces no advisory for a clean (unflagged) change
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/decision-gate/hooks/post-tool-use/gate-change.sh"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")

# Clean state
rm -f "/tmp/crow-gate-cooldown-${SESSION_HASH}"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl.lock"

# Seed the flags cache with a CLEAN assessment (no flags fired)
echo '{"ts":"2026-04-14T10:00:00Z","file":"src/safe.ts","severity":"clean","flags":[],"type":"source_code"}' > "/tmp/crow-flags-${SESSION_HASH}.jsonl"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: "src/safe.ts"}, hook_event_name: "PostToolUse"}')

STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/decision-gate" bash "$HOOK" 2>&1 >/dev/null || true)

FAIL=0
if [[ "$STDERR_OUT" == *"[Crow]"* ]]; then
  echo "FAIL: Clean change should NOT trigger advisory, got: $STDERR_OUT"; FAIL=1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "/tmp/crow-gate-cooldown-${SESSION_HASH}"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl.lock"

exit $FAIL
