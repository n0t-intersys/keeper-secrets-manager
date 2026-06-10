<#
.SYNOPSIS
    One-time onboarding for Keeper Secrets Manager on a Windows device.

.DESCRIPTION
    Installs the Python dependencies, then prompts for your personal Keeper
    one-time access token, redeems it, and stores the resulting KSM config in
    Windows Credential Manager. After this runs once, application code can pull
    secrets via the `ksm` helper with no token and no config file on disk.

    The one-time token is single-use and (by default) locked to this device's
    external IP. Get yours from a Secrets Manager admin (see README.md).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup\Setup-KSM.ps1
#>

[CmdletBinding()]
param(
    # Optionally pass the token non-interactively (e.g. for scripted setup).
    [string]$Token,

    # Skip adding the Get-KsmValue auto-import to the PowerShell profile.
    [switch]$NoProfileImport
)

$ErrorActionPreference = "Stop"

# Resolve repo paths relative to this script so it works from any cwd.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$KsmDir    = Join-Path $RepoRoot "ksm"

Write-Host "=== Keeper Secrets Manager device setup ===" -ForegroundColor Cyan

# 1. Locate Python (works on Windows PowerShell 5.1 and PowerShell 7+).
$pythonExe = $null
$cmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $cmd) { $cmd = Get-Command python3 -ErrorAction SilentlyContinue }
if ($cmd) { $pythonExe = $cmd.Source }
if (-not $pythonExe) {
    # Fallback: per-user python.org install location. PATH may not be refreshed
    # yet when this runs right after a silent install (e.g. from the installer).
    $cand = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
    if ($cand) { $pythonExe = $cand.FullName }
}
if (-not $pythonExe) {
    throw "Python 3.9+ is required but was not found. Install it from https://www.python.org/downloads/windows/ and re-run."
}
Write-Host "Using Python: $pythonExe"

# 2. Install the ksm package (editable) plus its dependencies. Editable means
#    `import ksm` works from ANY directory and code edits take effect with no
#    reinstall. Dependencies are declared in pyproject.toml.
Write-Host "Installing the ksm package and dependencies (editable) ..."
& $pythonExe -m pip install --upgrade -e $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "pip install failed." }

# 3. Obtain the one-time token (masked prompt unless passed as a parameter).
if (-not $Token) {
    $secure = Read-Host -AsSecureString "Paste your Keeper one-time access token (e.g. US:XXXX...)"
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
if ([string]::IsNullOrWhiteSpace($Token)) { throw "No token provided." }

# 4. Redeem the token. Pass it via env var so it never lands in the command
#    line / process list / shell history.
Write-Host "Redeeming token and storing config in Windows Credential Manager ..."
$env:KSM_TOKEN = $Token.Trim()
try {
    & $pythonExe (Join-Path $KsmDir "bootstrap.py")
    $exit = $LASTEXITCODE
} finally {
    Remove-Item Env:\KSM_TOKEN -ErrorAction SilentlyContinue
    $Token = $null
}
if ($exit -ne 0) { throw "Token redemption failed. The token may be expired, already used, or IP-locked to another network." }

# 5. Verify by loading the config back and listing accessible records.
Write-Host "Verifying access ..."
& $pythonExe (Join-Path $KsmDir "bootstrap.py") --verify
if ($LASTEXITCODE -ne 0) { throw "Verification failed." }

# 6. Make Get-KsmValue available in every new PowerShell session (idempotent).
#    Adds an Import-Module line to the user's profile so PowerShell consumers
#    don't have to import the module manually. Skip with -NoProfileImport.
if (-not $NoProfileImport) {
    $modulePath  = Join-Path $KsmDir "Ksm.psm1"
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }
    $already = Select-String -Path $profilePath -SimpleMatch $modulePath -Quiet -ErrorAction SilentlyContinue
    if (-not $already) {
        Add-Content -Path $profilePath -Value "Import-Module `"$modulePath`""
        Write-Host "Registered KSM module auto-import in your PowerShell profile."
    } else {
        Write-Host "KSM module auto-import already present in your PowerShell profile."
    }
}

Write-Host ""
Write-Host "Done. Your team's code can now read secrets without the token." -ForegroundColor Green
Write-Host "Examples: examples\example_usage.py (Python), examples\KeeperKSM-Example.ps1 (PowerShell)." -ForegroundColor Green
Write-Host "Open a NEW PowerShell window, then 'Get-KsmValue' is available everywhere." -ForegroundColor Green
