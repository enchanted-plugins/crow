#!/usr/bin/env bash
# Test: score-change.sh assesses a benign change as "clean" — no flags, no score,
#       and NO trust.json (the plugin is stateless; it never writes a trust file).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
TRACK_HOOK="${REPO_ROOT}/plugins/change-tracker/hooks/post-tool-use/track-change.sh"
SCORE_HOOK="${REPO_ROOT}/plugins/trust-scorer/hooks/post-tool-use/score-change.sh"

# Create a benign source file (long enough not to trip very_short_file, no weak crypto)
TMPDIR_TEST=$(mktemp -d)
TEST_FILE="${TMPDIR_TEST}/util.ts"
printf 'export function add(a, b) {\n  return a + b;\n}\nexport function sub(a, b) {\n  return a - b;\n}\nexport const K = 42;\n' > "$TEST_FILE"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")

# Clean state
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl.lock"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  --arg file "$TEST_FILE" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: $file}, hook_event_name: "PostToolUse"}')

# Run change-tracker first (provides session cache data)
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$TRACK_HOOK" 2>/dev/null

# Run trust-scorer, capture stderr
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/trust-scorer" bash "$SCORE_HOOK" 2>&1 >/dev/null || true)

FAIL=0

# 1. NO trust.json — the plugin is stateless.
if [[ -f "${REPO_ROOT}/plugins/trust-scorer/state/trust.json" ]]; then
  echo "FAIL: trust.json must NOT be created (plugin is stateless)"; FAIL=1
fi

# 2. A change_flagged metric with severity "clean" was recorded.
METRICS="${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
if [[ ! -f "$METRICS" ]] || ! grep -q '"event":"change_flagged"' "$METRICS"; then
  echo "FAIL: no change_flagged metric recorded"; FAIL=1
elif ! grep -q '"severity":"clean"' "$METRICS"; then
  echo "FAIL: benign change should be severity clean, got: $(cat "$METRICS")"; FAIL=1
fi

# 3. stderr shows the quiet clean line, and NO numeric score anywhere.
if [[ "$STDERR_OUT" != *"clean"* ]]; then
  echo "FAIL: expected 'clean' in stderr, got: $STDERR_OUT"; FAIL=1
fi
if grep -qiE 'trust:|"score"|"alpha"|"beta"' "$METRICS" 2>/dev/null; then
  echo "FAIL: metrics must not contain score/alpha/beta/trust"; FAIL=1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -rf "$TMPDIR_TEST"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/changes.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/change-tracker/state/metrics.jsonl.lock"
rm -f "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl.lock"

exit $FAIL
