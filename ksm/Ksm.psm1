<#
    Ksm.psm1 - PowerShell module for reading secrets from Keeper Secrets Manager.

    Import it in any .ps1 script, then call Get-KsmValue:

        Import-Module "C:\path\to\keeper-secrets-manager\ksm\Ksm.psm1"
        $pw = Get-KsmValue "RecordUID/field/password"

    Under the hood it calls the Python ksm\get.py bridge, which loads the
    config from Windows Credential Manager (populated once by Setup-KSM.ps1).
#>

# Repo root = parent of the ksm\ folder this module lives in.
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-KsmValue {
    <#
    .SYNOPSIS
        Return a single secret value using Keeper Notation.
    .EXAMPLE
        $pw = Get-KsmValue "RecordUID/field/password"
    .EXAMPLE
        $secure = Get-KsmValue "Prod DB/field/password" -AsSecureString
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Notation,
        [switch]$AsSecureString
    )

    $getScript = Join-Path $script:RepoRoot "ksm\get.py"
    $value = & python $getScript $Notation
    if ($LASTEXITCODE -ne 0) { throw "KSM lookup failed for: $Notation" }

    if ($AsSecureString) {
        return (ConvertTo-SecureString -String $value -AsPlainText -Force)
    }
    return $value
}

Export-ModuleMember -Function Get-KsmValue
