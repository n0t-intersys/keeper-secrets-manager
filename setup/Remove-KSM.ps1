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

# Locate Python.
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) {
    throw "Python was not found on PATH; cannot reach the credential store to remove the config."
}
$pythonExe = $python.Source

# Delete the config entry from Windows Credential Manager.
Write-Host "Removing KSM config from Windows Credential Manager ..."
& $pythonExe (Join-Path $KsmDir "bootstrap.py") --remove
if ($LASTEXITCODE -ne 0) { throw "Failed to remove KSM config." }

# Optionally remove the Python dependencies.
if ($UninstallDeps) {
    Write-Host "Uninstalling Python dependencies ..."
    & $pythonExe -m pip uninstall -y keeper-secrets-manager-core keyring
}

Write-Host ""
Write-Host "Local removal complete." -ForegroundColor Green
Write-Host "Reminder: ask a Keeper admin to remove this client device from the" -ForegroundColor Yellow
Write-Host "Application in the Vault to fully revoke access." -ForegroundColor Yellow
