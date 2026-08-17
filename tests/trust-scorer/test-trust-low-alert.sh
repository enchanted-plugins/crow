#!/usr/bin/env bash
# Test: score-change.sh fires a CRITICAL stderr advisory when a config change
#       exposes a secret — and emits flags, not a numeric score.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
TRACK_HOOK="${REPO_ROOT}/plugins/change-tracker/hooks/post-tool-use/track-change.sh"
SCORE_HOOK="${REPO_ROOT}/plugins/trust-scorer/hooks/post-tool-use/score-change.sh"

# Create a sensitive config file (.env) with an exposed live secret
TMPDIR_TEST=$(mktemp -d)
TEST_FILE="${TMPDIR_TEST}/.env"
echo "STRIPE_KEY=sk_live_abcdef0123456789ABCDEF" > "$TEST_FILE"

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

# Run change-tracker first, then trust-scorer
printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/change-tracker" bash "$TRACK_HOOK" 2>/dev/null
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/trust-scorer" bash "$SCORE_HOOK" 2>&1 >/dev/null || true)

FAIL=0

# 1. An advisory fired
if [[ "$STDERR_OUT" != *"[Crow]"* ]]; then
  echo "FAIL: expected '[Crow]' advisory, got: $STDERR_OUT"; FAIL=1
fi

# 2. Severity is CRITICAL (exposed_secrets)
if [[ "$STDERR_OUT" != *"CRITICAL"* ]]; then
  echo "FAIL: exposed secret should be CRITICAL, got: $STDERR_OUT"; FAIL=1
fi

# 3. The exposed_secrets flag is recorded in metrics
METRICS="${REPO_ROOT}/plugins/trust-scorer/state/metrics.jsonl"
if ! grep -q 'exposed_secrets' "$METRICS" 2>/dev/null; then
  echo "FAIL: exposed_secrets flag not recorded in metrics"; FAIL=1
fi

# 4. No numeric trust score anywhere
if [[ "$STDERR_OUT" == *"trust:"* ]] || grep -qiE '"score"|"alpha"|"beta"' "$METRICS" 2>/dev/null; then
  echo "FAIL: no numeric trust score should appear; stderr: $STDERR_OUT"; FAIL=1
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
