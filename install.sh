#!/usr/bin/env bash
#
# wild-west plugins — one-shot installer (macOS / Linux)
#
#   mkdir my-tenant && cd my-tenant
#   curl -fsSL https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/install.sh | bash
#
# Runs FROM the tenant directory (your current dir). It:
#   1. checks prerequisites (claude, git, a JSON tool)
#   2. prompts for your beta access token (never stored in this script)
#   3. sets up git credential-store auth for the private marketplace clone
#   4. adds the marketplace + installs the plugin --scope local into THIS dir
#   5. writes the download token(s) into this dir's .claude/settings.local.json
#
# Everything is parameterizable via env vars (defaults target the STAGING mirror):
#   WW_MKT_REPO   github owner/repo of the marketplace   (default: DuaneNielsen/wild-west-marketplace-staging)
#   WW_MKT_NAME   the marketplace NAME to install from   (default: basename of WW_MKT_REPO)
#   WW_PLUGIN     which plugin to install                (default: claude-thunder)
#   WW_BETA_TOKEN beta PAT (skips the prompt; for CI)    (default: prompt on /dev/tty)
#
set -euo pipefail

WW_MKT_REPO="${WW_MKT_REPO:-DuaneNielsen/wild-west-marketplace-staging}"
WW_MKT_NAME="${WW_MKT_NAME:-$(basename "$WW_MKT_REPO")}"
WW_PLUGIN="${WW_PLUGIN:-claude-thunder}"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- 0. prerequisites -------------------------------------------------------
say "Checking prerequisites"
command -v claude >/dev/null 2>&1 || die "Claude Code ('claude') is not installed or not on PATH. Install it: https://claude.com/claude-code"
ok "claude found: $(command -v claude)"
command -v git >/dev/null 2>&1 || die "git is not installed or not on PATH. It is required — 'claude plugin marketplace add' clones the private marketplace over git. Install it: https://git-scm.com/downloads"
ok "git found: $(command -v git)"
# JSON editor for the settings merge (prefer python3, fall back to jq).
if command -v python3 >/dev/null 2>&1; then JSON_TOOL=python3
elif command -v jq >/dev/null 2>&1; then JSON_TOOL=jq
else die "need either python3 or jq to write settings.local.json (macOS: 'brew install jq'; Debian/Ubuntu: 'sudo apt-get install jq')"; fi
ok "JSON tool: $JSON_TOOL"

# Safety: the tenant dir is the CURRENT dir. Refuse to scope-install straight into \$HOME.
TENANT_DIR="$PWD"
[ "$TENANT_DIR" != "$HOME" ] || die "Run this from a NEW tenant directory, not your home dir (mkdir my-tenant && cd my-tenant, then re-run)."
say "Tenant directory: $TENANT_DIR"

# --- 1. beta token ----------------------------------------------------------
if [ -z "${WW_BETA_TOKEN:-}" ]; then
  [ -e /dev/tty ] || die "No terminal to prompt for the token. Set WW_BETA_TOKEN=... in the environment and re-run."
  printf '\033[1;36m==>\033[0m Paste your beta access token (shown as *): ' > /dev/tty
  # Echo one * per character so a paste is visibly received (the value itself is never shown).
  WW_BETA_TOKEN=""
  while IFS= read -rs -n1 ch < /dev/tty && [ -n "$ch" ]; do
    if [ "$ch" = "$(printf '\x7f')" ] || [ "$ch" = "$(printf '\b')" ]; then
      if [ -n "$WW_BETA_TOKEN" ]; then
        WW_BETA_TOKEN="${WW_BETA_TOKEN%?}"
        printf '\b \b' > /dev/tty
      fi
    else
      WW_BETA_TOKEN="$WW_BETA_TOKEN$ch"
      printf '*' > /dev/tty
    fi
  done
  printf '\n' > /dev/tty
fi
[ -n "${WW_BETA_TOKEN:-}" ] || die "No token provided."
ok "token captured (${#WW_BETA_TOKEN} chars)"

# --- 2. clone auth: github.com-scoped credential store -----------------------
# 'marketplace add' clones a PRIVATE repo from a plain terminal (outside any Claude
# session), so it can't read workspace config. We use git's credential store — but
# scoped to github.com ONLY, with a dedicated credential file:
#   - credential.https://github.com.helper "" resets the helper list FOR GITHUB.COM
#     ONLY (neutralizes GUI keychains / GCM that can't prompt headlessly), leaving the
#     user's global credential.helper and every other host (corp GHE, gitlab, ...)
#     completely untouched.
#   - the store writes to ~/.wild-west-git-credentials, NOT the user's ~/.git-credentials.
# clean.sh removes exactly this section + this file and nothing else.
say "Configuring github.com-scoped git credential auth (your existing git config is not touched)"
CRED_FILE="$HOME/.wild-west-git-credentials"
# --replace-all: a re-run (second tenant, retry after a bad token) leaves multiple
# values on this key; a plain set would die with "cannot overwrite multiple values".
# The quoted --file survives git's shell-splitting of helper strings (paths with spaces).
git config --global --replace-all credential.https://github.com.helper ""
git config --global --add credential.https://github.com.helper "store --file=\"$CRED_FILE\""
printf 'https://x-access-token:%s@github.com\n' "$WW_BETA_TOKEN" > "$CRED_FILE"
chmod 0600 "$CRED_FILE"
if ! git ls-remote "https://github.com/$WW_MKT_REPO.git" HEAD >/dev/null 2>&1; then
  die "Cannot reach https://github.com/$WW_MKT_REPO.git with that token.
       A 404 means the token lacks 'Contents: read' on $WW_MKT_REPO (not a 403/format issue)."
fi
ok "clone auth verified against $WW_MKT_REPO"

# --- 3. marketplace add + scoped install ------------------------------------
# Idempotent: a second tenant on the same machine already has the marketplace.
# Match the marketplace NAME EXACTLY via --json (never a substring/regex match) —
# "$WW_MKT_NAME" and "$WW_MKT_NAME-staging" are prefix-related, so a plain `grep`
# would let a registered "...-staging" marketplace satisfy the check for the
# non-staging name (and vice versa).
mkt_already_added() {
  local name="$1"
  if [ "$JSON_TOOL" = python3 ]; then
    claude plugin marketplace list --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = []
sys.exit(0 if any(m.get("name") == sys.argv[1] for m in data) else 1)
' "$name"
  else
    claude plugin marketplace list --json 2>/dev/null | jq -e --arg n "$name" 'any(.[]?; .name == $n)' >/dev/null 2>&1
  fi
}
if mkt_already_added "$WW_MKT_NAME"; then
  ok "marketplace $WW_MKT_NAME already added — skipping add"
else
  say "Adding marketplace: $WW_MKT_REPO"
  claude plugin marketplace add "https://github.com/$WW_MKT_REPO.git"
fi
say "Installing $WW_PLUGIN@$WW_MKT_NAME --scope local (into $TENANT_DIR)"
claude plugin install "$WW_PLUGIN@$WW_MKT_NAME" --scope local
[ -f "$TENANT_DIR/.claude/settings.local.json" ] || die "--scope local did not create $TENANT_DIR/.claude/settings.local.json"
ok "installed; scoped-enable file present"

# --- 4. write the download token(s) into settings.local.json ----------------
# claude-thunder needs BOTH keys; dx-done/telemetry read DX_DONE_TOKEN, thunder reads
# THUNDER_DOWNLOAD_TOKEN. dx-done-only installs get just DX_DONE_TOKEN.
SETTINGS="$TENANT_DIR/.claude/settings.local.json"
say "Writing download token(s) into $SETTINGS"
if [ "$JSON_TOOL" = python3 ]; then
  python3 - "$SETTINGS" "$WW_BETA_TOKEN" "$WW_PLUGIN" <<'PY'
import json, os, sys
path, tok, plugin = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f: data = json.load(f)
    except Exception: data = {}
env = data.get("env") or {}
env["DX_DONE_TOKEN"] = tok
if plugin == "claude-thunder":
    env["THUNDER_DOWNLOAD_TOKEN"] = tok
data["env"] = env
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
else
  tmp="$(mktemp)"
  if [ "$WW_PLUGIN" = claude-thunder ]; then
    jq --arg t "$WW_BETA_TOKEN" '.env = ((.env // {}) + {DX_DONE_TOKEN: $t, THUNDER_DOWNLOAD_TOKEN: $t})' "$SETTINGS" > "$tmp"
  else
    jq --arg t "$WW_BETA_TOKEN" '.env = ((.env // {}) + {DX_DONE_TOKEN: $t})' "$SETTINGS" > "$tmp"
  fi
  mv "$tmp" "$SETTINGS"
fi
ok "download token(s) written"

# --- done -------------------------------------------------------------------
cat <<EOF

$(printf '\033[1;32mInstall complete.\033[0m') Next steps (run from THIS directory: $TENANT_DIR):

  1. Launch Claude Code here:   claude
  2. On first turn, Claude fetches the binaries (authenticated by the token you just
     stored) and offers to configure your DXO2 tenant. Set up dx-done FIRST — thunder
     is downstream (its agent token is minted by 'dx-done config generate-agent-token').
  3. Paste your DXO2 user token yourself into DXDONE_USER_TOKEN_DEFAULT in this
     directory's .claude/settings.local.json when prompted.

To undo everything (plugins, marketplace, the github.com-scoped credential, tenant
.claude), run clean.sh from this directory. Your beta token lives in plaintext in
~/.wild-west-git-credentials and this dir's .claude/settings.local.json — clean.sh wipes
both. Your own git config and ~/.git-credentials are never touched.
EOF
