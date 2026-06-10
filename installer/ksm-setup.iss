; ============================================================================
;  KSM Team Tools - Inno Setup installer
;
;  Produces a per-user, double-click installer that:
;    1. Silently installs a real python.org interpreter (only if none is found)
;    2. Lays down the ksm tooling under %LOCALAPPDATA%\Programs\KSM
;    3. Runs Setup-KSM.ps1 (pip install -e .  ->  redeem one-time token  ->
;       store config in Windows Credential Manager  ->  verify)
;    4. On uninstall, runs Remove-KSM.ps1 (bootstrap.py --remove + profile clean)
;
;  Per-user by design: the token redeem (a keyring write) MUST run as the
;  interactive user, because Windows Credential Manager is DPAPI per-user
;  scoped. Do NOT convert this to a silent/SYSTEM/elevated machine install or
;  the secret lands in the wrong vault.
;
;  Build:  see installer\build.ps1  (downloads Python, runs ISCC.exe)
; ============================================================================

#define MyAppName "KSM Team Tools"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "n0t-intersys"
#define MyAppURL "https://github.com/n0t-intersys/keeper-secrets-manager"

; Filename of the bundled python.org installer (placed in installer\vendor\ by
; build.ps1). Override at compile time with: ISCC /DPythonInstaller=...
#ifndef PythonInstaller
  #define PythonInstaller "vendor\python-amd64.exe"
#endif

[Setup]
AppId={{8B6F3D2A-4C1E-4E7A-9B2D-1F2E3D4C5B6A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\KSM
DisableProgramGroupPage=yes
DisableDirPage=yes
; Per-user install ENFORCED: no admin prompt, no "all users" option. The token
; redeem writes to Credential Manager (DPAPI per-user), so an elevated/all-users
; install would store the secret under the wrong account. Do not add
; PrivilegesRequiredOverridesAllowed here.
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=KSM-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesEnvironment=yes
UninstallDisplayName={#MyAppName}
; This installer is unsigned; see docs for the SmartScreen "Run anyway" note.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; --- The tooling (exclude build/cache artifacts) ---
Source: "..\ksm\*";          DestDir: "{app}\ksm";        Flags: recursesubdirs ignoreversion; Excludes: "__pycache__\*,*.pyc,*.egg-info\*"
Source: "..\setup\*";        DestDir: "{app}\setup";      Flags: recursesubdirs ignoreversion
Source: "..\examples\*";     DestDir: "{app}\examples";   Flags: recursesubdirs ignoreversion
Source: "..\docs\*";         DestDir: "{app}\docs";       Flags: recursesubdirs ignoreversion
Source: "..\pyproject.toml"; DestDir: "{app}";            Flags: ignoreversion
Source: "..\requirements.txt"; DestDir: "{app}";          Flags: ignoreversion
Source: "..\README.md";      DestDir: "{app}";            Flags: ignoreversion
; --- Bundled Python installer. `dontcopy` = not installed normally; extracted
;     on demand via ExtractTemporaryFile() in [Code], auto-cleaned on exit. ---
Source: "{#PythonInstaller}"; Flags: dontcopy

[Code]
var
  PythonAlreadyPresent: Boolean;

{ Return True if a usable 'python' is already on PATH. }
function HasPython: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'), '/c where python >nul 2>&1', '',
                 SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure InitializeWizard;
begin
  PythonAlreadyPresent := HasPython;
end;

{ Skip the bundled Python install if the user already has Python. }
function NeedsPython: Boolean;
begin
  Result := not PythonAlreadyPresent;
end;

{ Run the onboarding after files are copied. We drive this from code (rather
  than the [Run] section) so we can install Python first, then run setup, and
  surface failures to the user. }
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PsArgs: string;
begin
  if CurStep = ssPostInstall then
  begin
    { 1. Install Python per-user, silently, only if needed. Extract the bundled
         installer on demand (dontcopy) so there's no reliance on temp-file
         delete ordering. }
    if NeedsPython then
    begin
      ExtractTemporaryFile('python-amd64.exe');
      if not Exec(ExpandConstant('{tmp}\python-amd64.exe'),
                  '/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_launcher=1',
                  '', SW_SHOW, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
      begin
        MsgBox('Python installation failed (code ' + IntToStr(ResultCode) +
               '). You can install Python 3.12 manually and re-run setup\Setup-KSM.ps1.',
               mbError, MB_OK);
        Exit;
      end;
    end;

    { 2. Run onboarding in a VISIBLE console so the user can paste the token.
         Setup-KSM.ps1 finds the freshly-installed per-user Python even though
         PATH isn't refreshed in this process. }
    PsArgs := '-NoProfile -ExecutionPolicy Bypass -File "' +
              ExpandConstant('{app}\setup\Setup-KSM.ps1') + '"';
    if not Exec('powershell.exe', PsArgs, '', SW_SHOW, ewWaitUntilTerminated, ResultCode)
       or (ResultCode <> 0) then
    begin
      MsgBox('Keeper setup did not complete (code ' + IntToStr(ResultCode) + ').' + #13#10 +
             'You can re-run it any time from:' + #13#10 +
             ExpandConstant('{app}\setup\Setup-KSM.ps1'),
             mbError, MB_OK);
    end;
  end;
end;

[UninstallRun]
; Clean up Credential Manager + PowerShell profile on uninstall.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup\Remove-KSM.ps1"""; \
  Flags: runhidden; RunOnceId: "RemoveKSMConfig"
