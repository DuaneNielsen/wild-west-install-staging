#!/usr/bin/env bash
#
# wild-west plugins — clean-all / reset to a clean slate (macOS / Linux)
#
#   cd my-tenant
#   curl -fsSL https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/clean.sh | bash
#
# Reverses everything install.sh set up:
#   - uninstalls the plugins (scoped to THIS dir)
#   - removes the marketplace (global)
#   - drops the git credential store (~/.git-credentials + the helper)
#   - deletes the marketplace clone + cache + this dir's .claude (token + config)
#
# Parameterizable (same defaults as install.sh):
#   WW_MKT_REPO  (default: DuaneNielsen/wild-west-marketplace-staging)
#   WW_MKT_NAME  (default: basename of WW_MKT_REPO)
#
set -euo pipefail

WW_MKT_REPO="${WW_MKT_REPO:-DuaneNielsen/wild-west-marketplace-staging}"
WW_MKT_NAME="${WW_MKT_NAME:-$(basename "$WW_MKT_REPO")}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }

TENANT_DIR="$PWD"
PLUGINS_DIR="$HOME/.claude/plugins"

say "Cleaning wild-west install (tenant dir: $TENANT_DIR, marketplace: $WW_MKT_NAME)"
say "⚠  Exit any 'claude' session running in this dir first, or it will rewrite cache state."

# (a) plugins (scoped to this dir) + marketplace (global) — best-effort
if [ -d "$TENANT_DIR/.claude" ]; then
  ( cd "$TENANT_DIR" && for p in claude-thunder claude-dx-done claude-telemetry claude-investigator; do
      claude plugin uninstall "$p" --scope local 2>/dev/null || true
    done )
fi
claude plugin marketplace remove "$WW_MKT_NAME" 2>/dev/null || true
ok "plugins + marketplace removed (best-effort)"

# (b) the github.com-scoped credential config install.sh added — and ONLY that.
#     The user's global credential.helper, ~/.git-credentials, and every other host's
#     auth are never touched.
rm -f "$HOME/.wild-west-git-credentials"
git config --global --remove-section credential.https://github.com 2>/dev/null || true
ok "github.com-scoped credential config dropped (your own git config untouched)"

# (c) marketplace clone + cache + catalog + this dir's .claude (token + config)
rm -rf "$PLUGINS_DIR/marketplaces/$WW_MKT_NAME" "$PLUGINS_DIR/cache/$WW_MKT_NAME"
rm -f  "$PLUGINS_DIR/plugin-catalog-cache.json"
rm -rf "$TENANT_DIR/.claude"
ok "clone + cache + tenant .claude wiped"

say "Clean slate done. Verify:  claude plugin marketplace list   (should NOT list $WW_MKT_NAME)"
