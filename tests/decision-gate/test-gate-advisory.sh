#!/usr/bin/env bash
# Test: gate-change.sh fires an advisory for a detector-flagged change
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

# Seed the flags cache (as trust-scorer would have, in the same PostToolUse event)
echo '{"ts":"2026-04-14T10:00:00Z","file":"src/risky.ts","severity":"HIGH","flags":["weak_crypto"],"type":"source_code"}' > "/tmp/crow-flags-${SESSION_HASH}.jsonl"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: "src/risky.ts"}, hook_event_name: "PostToolUse"}')

STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/decision-gate" bash "$HOOK" 2>&1 >/dev/null || true)

FAIL=0
if [[ "$STDERR_OUT" != *"[Crow]"* ]]; then
  echo "FAIL: Expected '[Crow]' in stderr, got: $STDERR_OUT"; FAIL=1
fi
if [[ "$STDERR_OUT" != *"HIGH"* ]] || [[ "$STDERR_OUT" != *"weak_crypto"* ]]; then
  echo "FAIL: Expected severity + flag in advisory, got: $STDERR_OUT"; FAIL=1
fi
if [[ "$STDERR_OUT" != *"Ask yourself"* ]]; then
  echo "FAIL: Expected adversarial questions in advisory, got: $STDERR_OUT"; FAIL=1
fi
if [[ "$STDERR_OUT" == *"trust:"* ]]; then
  echo "FAIL: advisory must not print a numeric trust score, got: $STDERR_OUT"; FAIL=1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "/tmp/crow-gate-cooldown-${SESSION_HASH}"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "/tmp/crow-flags-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl.lock"

exit $FAIL
