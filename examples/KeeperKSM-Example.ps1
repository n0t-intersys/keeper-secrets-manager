<#
.SYNOPSIS
    Example PowerShell script that reads secrets from Keeper instead of
    hard-coding them.

.PREREQUISITES
    1. Run setup\Setup-KSM.ps1 once on this device (redeems your token).
    2. Allow local scripts once per user:
         Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

.EXAMPLE
    .\examples\KeeperKSM-Example.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Load the KSM module. $PSScriptRoot is this script's folder (examples\),
# so the module is one level up under ksm\.
$ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) "ksm\Ksm.psm1"
Import-Module $ModulePath -Force

# --- Set your record's UID here ----------------------------------------------
# Find it in the Vault: open the record -> info/share menu -> Record UID.
$RecordUID = "RecordUID"

if ($RecordUID -eq "RecordUID") {
    Write-Warning "Edit this script and set `$RecordUID to a real Keeper record UID before running."
    return
}

# --- Read secrets by Keeper Notation: <RecordUID>/field/<name> ---------------

# Plain value (use it immediately; never Write-Host / log the secret itself):
$password = Get-KsmValue "$RecordUID/field/password"
Write-Host "Fetched password (length): $($password.Length)"

# Other field types:
# $login  = Get-KsmValue "$RecordUID/field/login"
# $url     = Get-KsmValue "$RecordUID/field/url"
# $apiKey = Get-KsmValue "$RecordUID/custom_field/API Key"

# --- Build a credential without the password touching a plain variable -------

$securePw = Get-KsmValue "$RecordUID/field/password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential("svc_user", $securePw)
Write-Host "Built PSCredential for: $($cred.UserName)"

# Example of using it (commented - point at your real target):
# Invoke-Command -ComputerName "DB01" -Credential $cred -ScriptBlock { hostname }
