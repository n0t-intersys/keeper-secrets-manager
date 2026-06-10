<#
.SYNOPSIS
    Remove Keeper Secrets Manager from this Windows device.

.DESCRIPTION
    Deletes the redeemed KSM config from Windows Credential Manager so this
    device can no longer pull secrets. Optionally uninstalls the Python
    dependencies as well.

    NOTE: This only cleans up the local device. To fully revoke access, an
    admin must also remove this client device from the Application in the
    Keeper Vault (see docs\TEAM-DEPLOYMENT-GUIDE.md).

.EXAMPLE
    .\setup\Remove-KSM.ps1
.EXAMPLE
    .\setup\Remove-KSM.ps1 -UninstallDeps
#>

[CmdletBinding()]
param(
    # Also pip-uninstall keeper-secrets-manager-core and keyring.
    [switch]$UninstallDeps
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$KsmDir    = Join-Path $RepoRoot "ksm"

Write-Host "=== Keeper Secrets Manager device removal ===" -ForegroundColor Cyan

# Locate Python (PATH first, then per-user python.org install).
$pythonExe = $null
$cmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $cmd) { $cmd = Get-Command python3 -ErrorAction SilentlyContinue }
if ($cmd) { $pythonExe = $cmd.Source }
if (-not $pythonExe) {
    $cand = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
    if ($cand) { $pythonExe = $cand.FullName }
}

# Delete the config entry from Windows Credential Manager (best-effort, so an
# uninstall never hard-fails on a cleanup step).
if ($pythonExe) {
    Write-Host "Removing KSM config from Windows Credential Manager ..."
    & $pythonExe (Join-Path $KsmDir "bootstrap.py") --remove
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not remove the config automatically. Delete the 'KeeperSecretsManager' entry in Windows Credential Manager manually."
    }
    if ($UninstallDeps) {
        Write-Host "Uninstalling Python dependencies ..."
        & $pythonExe -m pip uninstall -y keeper-secrets-manager-core keyring
    }
} else {
    Write-Warning "Python not found. Remove the 'KeeperSecretsManager' entry in Windows Credential Manager manually (Control Panel > Credential Manager > Windows Credentials)."
}

# Remove the auto-import line from the PowerShell profile so new shells don't
# try to import a module that may no longer exist.
$modulePath  = Join-Path $KsmDir "Ksm.psm1"
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path $profilePath) {
    $lines = @(Get-Content $profilePath)
    $kept  = @($lines | Where-Object { $_ -notlike "*$modulePath*" })
    if ($kept.Count -ne $lines.Count) {
        Set-Content -Path $profilePath -Value $kept
        Write-Host "Removed KSM module auto-import from your PowerShell profile."
    }
}

Write-Host ""
Write-Host "Local removal complete." -ForegroundColor Green
Write-Host "Reminder: ask a Keeper admin to remove this client device from the" -ForegroundColor Yellow
Write-Host "Application in the Vault to fully revoke access." -ForegroundColor Yellow
