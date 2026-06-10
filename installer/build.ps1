<#
.SYNOPSIS
    Build the KSM Team Tools installer (.exe) with Inno Setup.

.DESCRIPTION
    1. Downloads the official python.org Windows installer into installer\vendor\
       (cached; skipped if already present).
    2. Locates ISCC.exe (the Inno Setup command-line compiler).
    3. Compiles installer\ksm-setup.iss into installer\Output\KSM-Setup-<ver>.exe.

    Prerequisites:
      - Inno Setup 6 installed (https://jrsoftware.org/isdl.php), or pass -IsccPath.

.EXAMPLE
    .\installer\build.ps1
.EXAMPLE
    .\installer\build.ps1 -PythonVersion 3.12.8
#>

[CmdletBinding()]
param(
    [string]$PythonVersion = "3.12.8",
    [string]$IsccPath
)

$ErrorActionPreference = "Stop"

$InstallerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VendorDir    = Join-Path $InstallerDir "vendor"
$Iss          = Join-Path $InstallerDir "ksm-setup.iss"

# 1. Download the python.org installer (cached).
New-Item -ItemType Directory -Force -Path $VendorDir | Out-Null
$pyExe = Join-Path $VendorDir "python-amd64.exe"
if (-not (Test-Path $pyExe)) {
    $url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
    Write-Host "Downloading Python $PythonVersion from $url ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $pyExe
} else {
    Write-Host "Using cached Python installer: $pyExe"
}

# 2. Locate ISCC.exe.
if (-not $IsccPath) {
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) {
        $IsccPath = $cmd.Source
    } else {
        $candidates = @(
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
        )
        $IsccPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
}
if (-not $IsccPath -or -not (Test-Path $IsccPath)) {
    throw "ISCC.exe (Inno Setup compiler) not found. Install Inno Setup 6 or pass -IsccPath. Download: https://jrsoftware.org/isdl.php"
}
Write-Host "Using ISCC: $IsccPath"

# 3. Compile.
Write-Host "Compiling installer ..."
& $IsccPath $Iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." }

$out = Join-Path $InstallerDir "Output"
Write-Host ""
Write-Host "Done. Installer is in: $out" -ForegroundColor Green
Get-ChildItem $out -Filter *.exe | ForEach-Object { Write-Host "  $($_.Name)" }
