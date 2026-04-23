#!/usr/bin/env bash
# Crow installer. The 4 plugins are a coordinated pipeline; the `full`
# meta-plugin pulls them all in via one dependency-resolution pass.
set -euo pipefail

REPO="https://github.com/enchanted-plugins/raven"
RAVEN_DIR="${HOME}/.claude/plugins/raven"

step() { printf "\n\033[1;36m▸ %s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }

step "Crow installer"

# 1. Clone (or update) the monorepo so shared/*.sh and shared/scripts/*.py are
#    available locally. Plugins themselves are served via the marketplace
#    command below — the clone is just for supporting scripts.
if [[ -d "$RAVEN_DIR/.git" ]]; then
  git -C "$RAVEN_DIR" pull --ff-only --quiet
  ok "Updated existing clone at $RAVEN_DIR"
else
  git clone --depth 1 --quiet "$REPO" "$RAVEN_DIR"
  ok "Cloned to $RAVEN_DIR"
fi

# 2. Ensure hook scripts are executable (fresh clones on some filesystems lose +x).
chmod +x "$RAVEN_DIR"/plugins/*/hooks/*/*.sh 2>/dev/null || true
chmod +x "$RAVEN_DIR"/shared/*.sh 2>/dev/null || true
chmod +x "$RAVEN_DIR"/shared/scripts/*.py 2>/dev/null || true
ok "Hook scripts marked executable"

cat <<'EOF'

─────────────────────────────────────────────────────────────────────────
  Crow ships as 4 plugins that feed each other (change-tracker →
  trust-scorer → decision-gate → session-memory). The `full` meta-plugin
  lists all four as dependencies so one install pulls in the whole chain.
─────────────────────────────────────────────────────────────────────────

  Finish in Claude Code with TWO commands:

    /plugin marketplace add enchanted-plugins/raven
    /plugin install full@raven

  That installs all 4 plugins via dependency resolution. To cherry-pick
  a single plugin instead, use e.g. `/plugin install raven-trust-scorer@raven`.

  Verify with:   /plugin list
  Expected:      full + 4 plugins installed under the raven marketplace.

EOF
