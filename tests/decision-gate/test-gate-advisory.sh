#!/usr/bin/env bash
# Test: gate-change.sh fires advisory for files with low trust
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/decision-gate/hooks/pre-tool-use/gate-change.sh"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")

# Clean state
rm -f "/tmp/raven-gate-cooldown-${SESSION_HASH}"
rm -f "/tmp/raven-changes-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl.lock"

# Set up trust.json with a low-trust file
TRUST_DIR="${REPO_ROOT}/plugins/trust-scorer/state"
mkdir -p "$TRUST_DIR"
echo '{"src/risky.ts": {"alpha": 2.3, "beta": 5.7, "score": 0.29, "type": "source_code", "ts": "2026-04-14T10:00:00Z"}}' > "${TRUST_DIR}/trust.json"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: "src/risky.ts"}, hook_event_name: "PreToolUse"}')

# Run the hook and capture stderr
STDERR_OUT=""
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/decision-gate" bash "$HOOK" 2>&1 >/dev/null || true)

# Verify advisory message appeared
if [[ "$STDERR_OUT" != *"[Crow]"* ]]; then
  echo "FAIL: Expected '[Crow]' in stderr, got: $STDERR_OUT"
  rm -f "$MOCK_TRANSCRIPT" "${TRUST_DIR}/trust.json"
  exit 1
fi

# Verify trust score is mentioned
if [[ "$STDERR_OUT" != *"0.29"* ]] && [[ "$STDERR_OUT" != *"trust"* ]]; then
  echo "FAIL: Expected trust score in advisory, got: $STDERR_OUT"
  rm -f "$MOCK_TRANSCRIPT" "${TRUST_DIR}/trust.json"
  exit 1
fi

# Verify adversarial questions are present (low trust should trigger V5)
if [[ "$STDERR_OUT" != *"Ask yourself"* ]] && [[ "$STDERR_OUT" != *"?"* ]]; then
  echo "FAIL: Expected adversarial questions in advisory for low trust"
  rm -f "$MOCK_TRANSCRIPT" "${TRUST_DIR}/trust.json"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "/tmp/raven-gate-cooldown-${SESSION_HASH}"
rm -f "/tmp/raven-changes-${SESSION_HASH}.jsonl"
rm -f "${TRUST_DIR}/trust.json"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl.lock"

exit 0
