#!/usr/bin/env bash
# Test: gate-change.sh produces no advisory for high-trust files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
HOOK="${REPO_ROOT}/plugins/decision-gate/hooks/pre-tool-use/gate-change.sh"

MOCK_TRANSCRIPT=$(mktemp)
echo '{"role":"user","content":"test"}' > "$MOCK_TRANSCRIPT"

SESSION_HASH=$(md5sum "$MOCK_TRANSCRIPT" 2>/dev/null | cut -c1-8 || echo "test")

# Clean state
rm -f "/tmp/crow-gate-cooldown-${SESSION_HASH}"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl.lock"

# Set up trust.json with a high-trust file
TRUST_DIR="${REPO_ROOT}/plugins/trust-scorer/state"
mkdir -p "$TRUST_DIR"
echo '{"src/safe.ts": {"alpha": 8.5, "beta": 1.5, "score": 0.85, "type": "source_code", "ts": "2026-04-14T10:00:00Z"}}' > "${TRUST_DIR}/trust.json"

INPUT=$(jq -n \
  --arg transcript "$MOCK_TRANSCRIPT" \
  '{transcript_path: $transcript, cwd: "/tmp", tool_name: "Write", tool_input: {file_path: "src/safe.ts"}, hook_event_name: "PreToolUse"}')

# Run the hook and capture stderr
STDERR_OUT=""
STDERR_OUT=$(printf "%s" "$INPUT" | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugins/decision-gate" bash "$HOOK" 2>&1 >/dev/null || true)

# Verify NO advisory was emitted
if [[ "$STDERR_OUT" == *"[Crow]"* ]]; then
  echo "FAIL: High-trust file should NOT trigger advisory, got: $STDERR_OUT"
  rm -f "$MOCK_TRANSCRIPT" "${TRUST_DIR}/trust.json"
  exit 1
fi

# Cleanup
rm -f "$MOCK_TRANSCRIPT"
rm -f "/tmp/crow-gate-cooldown-${SESSION_HASH}"
rm -f "/tmp/crow-changes-${SESSION_HASH}.jsonl"
rm -f "${TRUST_DIR}/trust.json"
rm -f "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl"
rm -rf "${REPO_ROOT}/plugins/decision-gate/state/metrics.jsonl.lock"

exit 0
