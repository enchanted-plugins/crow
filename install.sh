#!/usr/bin/env bash
set -euo pipefail

VIGIL_DIR="${HOME}/.claude/plugins/vigil"

if [[ -d "$VIGIL_DIR" ]]; then
  echo "Vigil already installed at $VIGIL_DIR"
  echo "To update: cd $VIGIL_DIR && git pull"
  exit 0
fi

echo "Installing Vigil..."
git clone https://github.com/enchanted-plugins/vigil "$VIGIL_DIR"
chmod +x "$VIGIL_DIR"/plugins/*/hooks/*/*.sh
chmod +x "$VIGIL_DIR"/shared/*.sh
chmod +x "$VIGIL_DIR"/shared/scripts/*.py

echo ""
echo "Done. Run in Claude Code:"
echo ""
echo "  /plugin add $VIGIL_DIR/plugins/change-tracker"
echo "  /plugin add $VIGIL_DIR/plugins/trust-scorer"
echo "  /plugin add $VIGIL_DIR/plugins/decision-gate"
echo "  /plugin add $VIGIL_DIR/plugins/session-memory"
echo ""
echo "Or add the marketplace:"
echo "  /plugin marketplace add $VIGIL_DIR"
echo ""
echo "Start with change-tracker + trust-scorer — they're the foundation."
