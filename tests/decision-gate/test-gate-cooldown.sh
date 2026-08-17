#!/usr/bin/env bash
# Test: gate-change.sh respects cooldown between advisories
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

# Seed the flags cache with a flagged change
echo '{"ts":"2026-04-14T10:00:00Z","file":"src/risky.ts","severity":"HIGH","flags":["weak_crypto"],"type":"source_code"}' > "/tmp/crow-flags-${SESSION_HASH}.jsonl"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: "src/risky.ts"}, hook_event_name: "PostToolUse"}')

FAIL=0

# First call should fire advisory
STDERR1=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/decision-gate" bash "$HOOK" 2>&1 >/dev/null || true)
if [[ "$STDERR1" != *"[Crow]"* ]]; then
  echo "FAIL: First call should fire advisory, got: $STDERR1"; FAIL=1
fi

# Second call immediately should be suppressed by cooldown
STDERR2=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/decision-gate" bash "$HOOK" 2>&1 >/dev/null || true)
if [[ "$STDERR2" == *"[Crow]"* ]]; then
  echo "FAIL: Second call should be suppressed by cooldown, got: $STDERR2"; FAIL=1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "/tmp/crow-gate-cooldown-${SESSION_HASH}"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl.lock"

exit $FAIL
