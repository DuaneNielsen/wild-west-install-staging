# wild-west-install

One-shot installer + uninstaller scripts for the **wild-west** Claude Code plugins
(`claude-thunder`, which pulls in `claude-dx-done` + `claude-telemetry`).

> **Prerequisites:** [Claude Code](https://claude.com/claude-code) and
> [git](https://git-scm.com/downloads) must be installed and on your PATH. The scripts
> check both and stop with a clear message if either is missing. (git is required because
> `claude plugin marketplace add` clones the private marketplace over git.)

## Install

Create a directory for your tenant workspace and `cd` into it — this directory *is* your
tenant workspace, and you'll launch `claude` from it later. Then run:

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/install.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/install.ps1 | iex
```

You'll be prompted for your **beta access token** (hidden input) — paste it now. The
script uses it to wire up git credential auth for the private marketplace, `marketplace
add`, a workspace-scoped `plugin install`, and writes the download token(s) into this
directory's `.claude/settings.local.json`.

- Needs **`Contents: read`** on the marketplace repo (clone) **and** the binary dist host
  (`dx-done-dist*`). A missing grant shows as **404**, not 403.
- Stored in plaintext in `~/.wild-west-git-credentials` (a dedicated file — your own
  `~/.git-credentials` is never touched) and this directory's
  `.claude/settings.local.json`. **Uninstall** (below) wipes both.
- The credential override is scoped to `github.com` only (a
  `credential.https://github.com.helper` section) — your global `credential.helper`,
  corp/GHE hosts, and other accounts are untouched. (Only caveat: if you already had your
  own `credential.https://github.com.helper` entries, install shadows them and uninstall
  removes the section — re-add yours after.)
- The script **never embeds a token** — this repo is public. You paste it at runtime (or
  pass `WW_BETA_TOKEN` non-interactively).

After it finishes, launch `claude` from that directory and follow the first-run guidance
(set up **dx-done first** — thunder is downstream).

> **Windows note:** let Claude run `dx-done` / `thunder` through its **Bash tool** (Git
> Bash), never the PowerShell tool — the plugin `bin/` is only on the Bash tool's PATH.
> Claude's SessionStart guidance says this automatically.

## Uninstall

Removes the plugins, the marketplace, the git credential, and the tenant directory's
`.claude` (which holds the token + config). Run from inside the tenant directory:

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/clean.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/clean.ps1 | iex
```

## Configuration (advanced)

Defaults target the **staging** marketplace. Override via environment variables before
running (works on both shells):

| Var | Default | Meaning |
|---|---|---|
| `WW_MKT_REPO` | `DuaneNielsen/wild-west-marketplace-staging` | github `owner/repo` of the marketplace to clone |
| `WW_MKT_NAME` | *(basename of `WW_MKT_REPO`)* | the marketplace **name** to `install ...@<name>` from |
| `WW_PLUGIN` | `claude-thunder` | which plugin to install (`claude-dx-done` for the core only) |
| `WW_BETA_TOKEN` | *(prompts)* | supply the token non-interactively (e.g. CI); skips the prompt |

Example — install the **release** marketplace, dx-done only:
```bash
WW_MKT_REPO=DuaneNielsen/wild-west-marketplace WW_PLUGIN=claude-dx-done \
  curl -fsSL https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/install.sh | bash
```

**Testing an install-script change before it ships?** These scripts themselves are
staged separately, at `DuaneNielsen/wild-west-install-staging` — fetch from there instead
of `wild-west-install/main` to exercise an unpromoted change directly:
```bash
curl -fsSL https://raw.githubusercontent.com/DuaneNielsen/wild-west-install-staging/main/install.sh | bash
```
This is exactly what the install-smoke Release Gate itself fetches when it runs against
the staging marketplace — see `projects/install-smoke/UAT.md` for the full staging walk.

---

*Source of truth for these scripts lives in the wild-west monorepo at
`projects/install-scripts/`; this repo is the published, public copy.*
