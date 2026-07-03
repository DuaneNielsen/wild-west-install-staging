<#
  wild-west plugins - clean-all / reset to a clean slate (Windows / PowerShell)

    cd my-tenant
    irm https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/clean.ps1 | iex

  Reverses everything install.ps1 set up:
    - uninstalls the plugins (scoped to THIS dir)
    - removes the marketplace (global)
    - drops the git credential store (~/.git-credentials + the helper)
    - deletes the marketplace clone + cache + this dir's .claude (token + config)

  Parameterizable (same defaults as install.ps1):
    $env:WW_MKT_REPO  (default: DuaneNielsen/wild-west-marketplace-staging)
    $env:WW_MKT_NAME  (default: basename of WW_MKT_REPO)
#>
$ErrorActionPreference = 'Stop'

function Say { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function OK  { param($m) Write-Host "  [ok] $m" -ForegroundColor Green }

$MktRepo = if ($env:WW_MKT_REPO) { $env:WW_MKT_REPO } else { 'DuaneNielsen/wild-west-marketplace-staging' }
$MktName = if ($env:WW_MKT_NAME) { $env:WW_MKT_NAME } else { ($MktRepo -split '/')[-1] }

$TenantDir  = (Get-Location).Path
$PluginsDir = Join-Path $HOME ".claude\plugins"

Say "Cleaning wild-west install (tenant dir: $TenantDir, marketplace: $MktName)"
Say "Exit any 'claude' session running in this dir first, or it will rewrite cache state."

# (a) plugins (scoped) + marketplace (global) - best-effort
#     NOTE: on Windows PowerShell 5.1, a native command that writes to a redirected
#     stderr (2>$null) surfaces as a terminating NativeCommandError under EAP=Stop -
#     even on "nothing to remove" outcomes. try/catch keeps these best-effort/idempotent
#     so the script always reaches step (c).
if (Test-Path (Join-Path $TenantDir ".claude")) {
  Push-Location $TenantDir
  foreach ($p in "claude-thunder","claude-dx-done","claude-telemetry","claude-investigator") {
    try { claude plugin uninstall $p --scope local 2>$null } catch {}
  }
  Pop-Location
}
try { claude plugin marketplace remove $MktName 2>$null } catch {}
OK "plugins + marketplace removed (best-effort)"

# (b) the github.com-scoped credential config install.ps1 added - and ONLY that.
#     The user's global credential.helper, ~\.git-credentials, and every other host's
#     auth are never touched.
Remove-Item -Force "$HOME\.wild-west-git-credentials" -ErrorAction SilentlyContinue
try { git config --global --remove-section credential.https://github.com 2>$null } catch {}
OK "github.com-scoped credential config dropped (your own git config untouched)"

# (c) marketplace clone + cache + catalog + this dir's .claude
Remove-Item -Recurse -Force (Join-Path $PluginsDir "marketplaces\$MktName") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $PluginsDir "cache\$MktName") -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $PluginsDir "plugin-catalog-cache.json") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $TenantDir ".claude") -ErrorAction SilentlyContinue
OK "clone + cache + tenant .claude wiped"

Say "Clean slate done. Verify:  claude plugin marketplace list   (should NOT list $MktName)"
