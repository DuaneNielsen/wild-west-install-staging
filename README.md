# wild-west-install

One-shot installer + clean-up scripts for the **wild-west** Claude Code plugins
(`claude-thunder`, which pulls in `claude-dx-done` + `claude-telemetry`).

You create a directory, run the installer inside it, paste your **beta access token**,
and it wires up the whole install: git credential auth for the private marketplace,
`marketplace add`, a workspace-scoped `plugin install`, and the download token(s) in that
directory's `.claude/settings.local.json`. The directory *is* your tenant workspace —
launch `claude` from it.

> **Prerequisites:** [Claude Code](https://claude.com/claude-code) and
> [git](https://git-scm.com/downloads) must be installed and on your PATH. The scripts
> check both and stop with a clear message if either is missing. (git is required because
> `claude plugin marketplace add` clones the private marketplace over git.)

## Install

**macOS / Linux**
```bash
mkdir my-tenant && cd my-tenant
curl -fsSL https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/install.sh | bash
```

**Windows (PowerShell)**
```powershell
mkdir my-tenant; cd my-tenant
irm https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/install.ps1 | iex
```

Both prompt for your beta token (hidden input) and run from the current directory. After
it finishes, launch `claude` from that directory and follow the first-run guidance
(set up **dx-done first** — thunder is downstream).

> **Windows note:** let Claude run `dx-done` / `thunder` through its **Bash tool** (Git
> Bash), never the PowerShell tool — the plugin `bin/` is only on the Bash tool's PATH.
> Claude's SessionStart guidance says this automatically.

## Clean up (reset to a clean slate)

Removes the plugins, the marketplace, the git credential, and the tenant directory's
`.claude` (which holds the token + config).

**macOS / Linux**
```bash
cd my-tenant
curl -fsSL https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/clean.sh | bash
```

**Windows (PowerShell)**
```powershell
cd my-tenant
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

## Token & scope notes

- Your beta token needs **`Contents: read`** on the marketplace repo (clone) **and** on
  the binary dist host (`dx-done-dist*`). A missing grant shows as **404**, not 403.
- The token is stored in plaintext in `~/.wild-west-git-credentials` (a dedicated file —
  your own `~/.git-credentials` is never touched) and the tenant's
  `.claude/settings.local.json`. `clean.sh` / `clean.ps1` wipe both.
- The scripts **do not modify your existing git auth.** The credential override is scoped
  to `github.com` only (a `credential.https://github.com.helper` section); your global
  `credential.helper`, corp/GHE hosts, and other accounts are untouched. `clean` removes
  exactly that section. (Only caveat: if you already had your own
  `credential.https://github.com.helper` entries, install shadows them and clean removes
  the section — re-add yours after.)
- The scripts **never embed a token** — this repo is public. You paste it at runtime (or
  pass `WW_BETA_TOKEN`).

---

*Source of truth for these scripts lives in the wild-west monorepo at
`projects/install-scripts/`; this repo is the published, public copy.*
