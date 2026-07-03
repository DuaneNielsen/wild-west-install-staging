<#
  wild-west plugins - one-shot installer (Windows / PowerShell)

    mkdir my-tenant; cd my-tenant
    irm https://raw.githubusercontent.com/DuaneNielsen/wild-west-install/main/install.ps1 | iex

  Runs FROM the tenant directory (your current dir). It:
    1. checks prerequisites (claude, git)
    2. prompts for your beta access token (never stored in this script)
    3. sets up git credential-store auth for the private marketplace clone
    4. adds the marketplace + installs the plugin --scope local into THIS dir
    5. writes the download token(s) into this dir's .claude\settings.local.json

  Parameterizable via env vars (defaults target the STAGING mirror):
    $env:WW_MKT_REPO   github owner/repo of the marketplace  (default: DuaneNielsen/wild-west-marketplace-staging)
    $env:WW_MKT_NAME   the marketplace NAME to install from  (default: basename of WW_MKT_REPO)
    $env:WW_PLUGIN     which plugin to install               (default: claude-thunder)
    $env:WW_BETA_TOKEN beta PAT (skips the prompt; for CI)   (default: prompt)
#>
$ErrorActionPreference = 'Stop'

function Say  { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function OK   { param($m) Write-Host "  [ok] $m" -ForegroundColor Green }
function Die  { param($m) Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

$MktRepo = if ($env:WW_MKT_REPO) { $env:WW_MKT_REPO } else { 'DuaneNielsen/wild-west-marketplace-staging' }
$MktName = if ($env:WW_MKT_NAME) { $env:WW_MKT_NAME } else { ($MktRepo -split '/')[-1] }
$Plugin  = if ($env:WW_PLUGIN)   { $env:WW_PLUGIN }   else { 'claude-thunder' }

# --- 0. prerequisites -------------------------------------------------------
Say "Checking prerequisites"
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Die "Claude Code ('claude') is not installed or not on PATH. Install it: https://claude.com/claude-code" }
OK "claude found"
if (-not (Get-Command git -ErrorAction SilentlyContinue))    { Die "git is not installed or not on PATH. It is required - 'claude plugin marketplace add' clones the private marketplace over git. Install Git for Windows: https://git-scm.com/download/win" }
OK "git found"

# Tenant dir = current dir. Refuse to scope-install straight into the home dir.
$TenantDir = (Get-Location).Path
if ($TenantDir -eq $HOME) { Die "Run this from a NEW tenant directory, not your home dir (mkdir my-tenant; cd my-tenant; then re-run)." }
Say "Tenant directory: $TenantDir"

# --- 1. beta token ----------------------------------------------------------
if ($env:WW_BETA_TOKEN) {
  $Token = $env:WW_BETA_TOKEN
} else {
  $sec = Read-Host -AsSecureString "Paste your beta access token (input hidden)"
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try   { $Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if ([string]::IsNullOrWhiteSpace($Token)) { Die "No token provided." }
OK "token captured ($($Token.Length) chars)"

# --- 2. clone auth: github.com-scoped credential store -----------------------
# 'marketplace add' clones a PRIVATE repo from a plain terminal. We scope the credential
# override to github.com ONLY: an empty first credential.https://github.com.helper entry
# resets the helper list FOR GITHUB.COM ONLY (neutralizes Git-for-Windows' Credential
# Manager, which can't prompt headlessly), leaving the user's global credential.helper
# and every other host (corp GHE, gitlab, ...) untouched. The store writes to a dedicated
# file, NOT the user's ~/.git-credentials. clean.ps1 removes exactly this and nothing else.
Say "Configuring github.com-scoped git credential auth (your existing git config is not touched)"
$CredFile = Join-Path $HOME ".wild-west-git-credentials"
# Git runs credential helpers through its POSIX shell: a backslash C:\Users\... path in
# the helper string gets mangled, so hand it forward slashes + quotes (spaces survive).
$CredFileGit = '"' + ($CredFile -replace '\\','/') + '"'
# --replace-all: a re-run (second tenant, retry after a bad token) leaves multiple
# values on this key; a plain set would die with "cannot overwrite multiple values".
git config --global --replace-all credential.https://github.com.helper ""
git config --global --add credential.https://github.com.helper "store --file=$CredFileGit"
# LF + no BOM: git credential-store silently rejects CRLF/BOM-tainted entries.
[System.IO.File]::WriteAllText($CredFile, "https://x-access-token:$Token@github.com`n", [System.Text.UTF8Encoding]::new($false))
# On Windows PowerShell 5.1, a native command that writes to a redirected stderr
# (2>$null) surfaces as a terminating NativeCommandError under EAP=Stop - even on
# expected failures like a 404. try/catch keeps $LASTEXITCODE authoritative so the
# actionable Die() message below still fires instead of a raw NativeCommandError.
try { git ls-remote "https://github.com/$MktRepo.git" HEAD 2>$null | Out-Null } catch {}
if ($LASTEXITCODE -ne 0) {
  Die "Cannot reach https://github.com/$MktRepo.git with that token. A 404 means the token lacks 'Contents: read' on $MktRepo (not a 403/format issue)."
}
OK "clone auth verified against $MktRepo"

# --- 3. marketplace add + scoped install ------------------------------------
# Idempotent: a second tenant on the same machine already has the marketplace.
try { $mktList = claude plugin marketplace list 2>$null | Out-String } catch { $mktList = "" }
if ($mktList -match [regex]::Escape($MktName)) {
  OK "marketplace $MktName already added - skipping add"
} else {
  Say "Adding marketplace: $MktRepo"
  claude plugin marketplace add "https://github.com/$MktRepo.git"
}
Say "Installing $Plugin@$MktName --scope local (into $TenantDir)"
claude plugin install "$Plugin@$MktName" --scope local
$Settings = Join-Path $TenantDir ".claude\settings.local.json"
if (-not (Test-Path $Settings)) { Die "--scope local did not create $Settings" }
OK "installed; scoped-enable file present"

# --- 4. write the download token(s) into settings.local.json ----------------
Say "Writing download token(s) into $Settings"
$j = Get-Content $Settings -Raw | ConvertFrom-Json
if (-not $j.env) { $j | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force }
$j.env | Add-Member -NotePropertyName DX_DONE_TOKEN -NotePropertyValue $Token -Force
if ($Plugin -eq 'claude-thunder') {
  $j.env | Add-Member -NotePropertyName THUNDER_DOWNLOAD_TOKEN -NotePropertyValue $Token -Force
}
$j | ConvertTo-Json -Depth 20 | Set-Content $Settings -Encoding utf8
OK "download token(s) written"

# --- done -------------------------------------------------------------------
Write-Host ""
Write-Host "Install complete." -ForegroundColor Green
Write-Host @"
Next steps (run from THIS directory: $TenantDir):

  1. Launch Claude Code here:   claude
  2. On first turn, Claude fetches the binaries (authenticated by the token you just
     stored) and offers to configure your DXO2 tenant. Set up dx-done FIRST - thunder
     is downstream (its agent token is minted by 'dx-done config generate-agent-token').
     NOTE: let Claude run 'dx-done'/'thunder' through its Bash tool (Git Bash), never the
     PowerShell tool - the plugin bin dir is only on the Bash tool PATH (#365).
  3. Paste your DXO2 user token yourself into DXDONE_USER_TOKEN_DEFAULT in this
     directory's .claude\settings.local.json when prompted.

To undo everything, run clean.ps1 from this directory. Your beta token lives in plaintext
in ~\.wild-west-git-credentials and this dir's .claude\settings.local.json - clean.ps1
wipes both. Your own git config and ~\.git-credentials are never touched.
"@
