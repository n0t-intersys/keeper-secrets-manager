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
    [string]$Token
)

$ErrorActionPreference = "Stop"

# Resolve repo paths relative to this script so it works from any cwd.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$KsmDir    = Join-Path $RepoRoot "ksm"

Write-Host "=== Keeper Secrets Manager device setup ===" -ForegroundColor Cyan

# 1. Locate Python (works on Windows PowerShell 5.1 and PowerShell 7+).
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) {
    throw "Python 3.9+ is required but was not found on PATH. Install it from https://www.python.org/downloads/windows/ and re-run."
}
$pythonExe = $python.Source
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

Write-Host ""
Write-Host "Done. Your team's code can now read secrets without the token." -ForegroundColor Green
Write-Host "Examples: examples\example_usage.py (Python), examples\KeeperKSM-Example.ps1 (PowerShell)." -ForegroundColor Green
