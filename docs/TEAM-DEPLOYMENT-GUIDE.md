# Keeper Secrets Manager (KSM) — Team Deployment Guide

A step-by-step guide for rolling KSM out to the team so everyone pulls secrets
from Keeper at runtime instead of hard-coding them.

- **Platform:** Windows (PowerShell 5.1+)
- **Language:** Python 3.9+ (`keeper-secrets-manager-core`)
- **Credential delivery:** one personal **one-time token per developer/device**
- **Where config lives:** **Windows Credential Manager** (no config file on disk)
- **Consumption:** Python (`from ksm import get_value`) and PowerShell (`Get-KsmValue`)

---

## 1. How it works

```
Admin (Keeper Vault)                Developer device (ONCE)               App code (every run)
--------------------                ----------------------                --------------------
Create KSM Application      ---->   Setup-KSM.ps1                          Python:
Grant folder/record access            - install Python + deps               from ksm import get_value
Generate one-time token     ---->     - paste one-time token                pw = get_value("RecordUID/field/password")
  (one per developer)                 - token redeemed (single use)
                                       - config -> Credential Manager      PowerShell:
                                                |                            Import-Module ksm\Ksm.psm1
                                                v                            $pw = Get-KsmValue "RecordUID/field/password"
                                     Windows Credential Manager <-----------------+
```

The one-time token is **single-use** and (by default) locked to the device's
external IP. After it's redeemed it's spent; the derived config saved in
Credential Manager is what the SDK uses from then on. No secret or config ever
lands in source control or a plaintext file.

---

## 2. Repository layout

| Path | Role | Who touches it |
|------|------|----------------|
| `setup/Setup-KSM.ps1` | One-time device onboarding (install deps, redeem token, verify) | Each developer, once |
| `setup/Remove-KSM.ps1` | Device teardown: delete config from Credential Manager (`-UninstallDeps` optional) | Offboarding/cleanup |
| `ksm/bootstrap.py` | Redeems token → stores config in Credential Manager; `--verify` / `--remove` modes | Called by the setup scripts |
| `ksm/ksm_client.py` | Python helper: `get_value`, `get_field`, `get_secret_by_title`, `get_secrets` | Imported by app code |
| `ksm/__init__.py` | Re-exports the helper functions as the `ksm` package | — |
| `ksm/config_store.py` | Credential Manager service/key names | — |
| `ksm/get.py` | Tiny CLI bridge so PowerShell can fetch one value | Called by Ksm.psm1 |
| `ksm/Ksm.psm1` | PowerShell module exposing `Get-KsmValue` | Imported by .ps1 scripts |
| `examples/example_usage.py` | Python example | Reference |
| `examples/KeeperKSM-Example.ps1` | PowerShell example | Reference |
| `requirements.txt` | Python dependencies | Setup |

---

## 3. Admin: issue access (one-time per project + per developer)

Do this in the **Keeper Vault UI** (Secrets Manager module) or **Keeper Commander**.

### 3a. Create the Application and grant records (Vault UI)
1. Open **Secrets Manager** → **Create Application** (e.g. `Team App`).
2. Add the **folders/records** the team needs. Use **read-only** unless writes
   are genuinely required (least privilege).
3. Save.

### 3b. Generate a one-time token per developer
1. In the Application, click **Generate Access Token**.
2. Copy the token (format `US:XXXX...`). It is shown **once** — capture it now.
3. Generate a **separate token for each developer** so access can be revoked
   individually and the blast radius stays small.
4. Send each developer their token over a secure channel (not email/chat in
   plaintext — use the vault's share feature or a secure note).

### Commander equivalent
```
secrets-manager app create "Team App"
secrets-manager share add --app "Team App" --secret <folder-or-record-uid> --editable off
secrets-manager client add --app "Team App"     # prints a one-time token; repeat per developer
```

> **IP locking:** Tokens lock to the device's external IP by default. For
> laptops that roam networks, add `--unlock-ip` when generating (or toggle the
> WAN-IP lock off in the UI). Prefer IP-locking when feasible.

---

## 4. Developer: one-time device setup

### 4a. Install Python (if not already present)
Option A — winget (built into Windows 11):
```powershell
winget install --id Python.Python.3.12 --source winget
```
Option B — installer: download from <https://www.python.org/downloads/windows/>,
and **check "Add python.exe to PATH"** during install.

Then **close and reopen PowerShell** and confirm:
```powershell
python --version
python -m pip --version
```
> If `python` opens the Microsoft Store instead, disable the alias:
> **Settings → Apps → Advanced app settings → App execution aliases →** turn OFF
> `python.exe` and `python3.exe`, then reopen PowerShell.

### 4b. Allow local scripts (once per user)
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### 4c. Run the setup script
From the repo root:
```powershell
.\setup\Setup-KSM.ps1
```
The script will:
1. Install Python deps from `requirements.txt`.
2. Prompt for your one-time token (input is masked).
3. Redeem it and store the config in **Windows Credential Manager**.
4. Verify by listing the records your Application can access.

Expected output:
```
Redeeming token and storing config in Windows Credential Manager ...
KSM config stored in Windows Credential Manager.
Verifying access ...
Success: this device can access N record(s).
Done. Your team's code can now read secrets without the token.
```
You only do this **once per device**. Re-run it any time you rotate your token.

---

## 5. Using secrets in code

### 5a. Find the RecordUID and field name
- In the Vault, open the record → its **UID** is in the info / "i" panel or the
  record's share menu. The UID is stable even if the record is renamed.
- **Keeper Notation** addresses a single field:
  - Standard field: `<RecordUID>/field/<name>` — e.g. `field/login`,
    `field/password`, `field/url`
  - Custom field (by its label): `<RecordUID>/custom_field/<label>`

### 5b. Python
Place your script **inside the repo** (so `import ksm` resolves), or add the
repo to `sys.path` (see Troubleshooting). Then:
```python
from ksm import get_value, get_field, get_secret_by_title

# Precise, by UID (recommended):
pw = get_value("RecordUID/field/password")

# By record title (readable, but breaks if the record is renamed):
user = get_field("Prod Database", "login")
api  = get_field("Payments API", "API Key", custom=True)

# Whole record:
rec = get_secret_by_title("Prod Database")
```

### 5c. PowerShell
```powershell
# Import the module (adjust the path to where the repo lives):
Import-Module "C:\path\to\keeper-secrets-manager\ksm\Ksm.psm1" -Force

# Plain value — use immediately, never log it:
$password = Get-KsmValue "RecordUID/field/password"

# As a SecureString for cmdlets that accept one:
$securePw = Get-KsmValue "RecordUID/field/password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential("svc_user", $securePw)
```
See `examples\KeeperKSM-Example.ps1` for a complete, runnable script.

---

## 6. Security do's and don'ts

**Do**
- Reference secrets by **UID/notation** in code — only the *reference* is committed.
- Grant each Application **only** the records it needs, read-only where possible.
- Issue **one token per developer**; revoke individually when someone offboards.
- Keep the config in **Credential Manager** (the default here) — no files on disk.

**Don't**
- Don't `Write-Host` / `print` / log the secret value.
- Don't paste the one-time token into chat/email or commit it.
- Don't share one token across the whole team.
- Don't commit `.env`, `*.json` config dumps, or `__pycache__` (add to `.gitignore`).

### Rotation & revocation
- **Rotate a developer's access:** generate a new token, have them re-run
  `Setup-KSM.ps1`.
- **Revoke a developer:** in the Vault Application, remove their **client
  device** — access is cut immediately, others are unaffected.
- **Rotate a secret value:** change it in the Vault; code picks up the new value
  on next fetch (no redeploy needed).

### Removing KSM from a device (offboarding / cleanup)
The redeemed config lives in **Windows Credential Manager** on each device, not
in a file. Removal has two parts:

1. **On the device** — delete the stored config:
   ```powershell
   .\setup\Remove-KSM.ps1                 # remove the config only
   .\setup\Remove-KSM.ps1 -UninstallDeps  # also pip-uninstall the SDK + keyring
   ```
   This is idempotent and safe to run even if nothing is stored.

2. **In the Vault (admin)** — remove this **client device** from the Application
   so the config can never be used again, even if a copy leaked. This is the
   authoritative revocation; the local step is just cleanup.

> Manual check (no script): open **Credential Manager → Windows Credentials**
> and look for the `KeeperSecretsManager` entry. `Remove-KSM.ps1` deletes it for
> you.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|--------|-------|-----|
| `Python was not found; run without arguments to install from the Microsoft Store` | Windows App-execution alias hijacks `python` | Settings → Apps → Advanced app settings → App execution aliases → turn OFF `python.exe`/`python3.exe`; reopen shell |
| `pip install failed` | Python/pip missing, proxy/SSL inspection, or `--user` conflict | `python -m ensurepip --upgrade`; behind proxy add `--proxy`; install without `--user` |
| `ModuleNotFoundError: No module named 'ksm'` | Script runs from outside the repo so the `ksm` package isn't on `sys.path` | Put the script inside the repo, **or** `setx`/`$env:PYTHONPATH` to the repo root, **or** add `sys.path.insert(0, r"C:\path\to\keeper-secrets-manager")` at the top |
| `Get-KsmValue : The term ... is not recognized` | The module wasn't imported in that script/session | Add `Import-Module "...\ksm\Ksm.psm1" -Force` before calling it |
| `Verification failed` / `KSM lookup failed` | Token expired/already used, IP-locked to another network, or wrong RecordUID | Re-issue token (+`--unlock-ip` if roaming); confirm the UID is one your Application was granted |
| `...cannot be loaded because running scripts is disabled` | Execution policy blocks .ps1 | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| Value returns empty / `no value found for notation` | Wrong field name or field type | Check notation: `field/<name>` vs `custom_field/<label>`; verify the field exists on the record |

Quick diagnostic (shows the real Python error instead of the wrapper's generic message):
```powershell
python .\ksm\get.py "RecordUID/field/password"
```

---

## 8. Rollout checklist

**Admin**
- [ ] Create the KSM Application and grant the needed records (read-only).
- [ ] Generate one one-time token per developer; distribute securely.
- [ ] Decide IP-lock vs `--unlock-ip` policy.

**Each developer**
- [ ] Install Python 3.9+ and confirm `python --version`.
- [ ] `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- [ ] Run `.\setup\Setup-KSM.ps1` and see "Success: this device can access N record(s)."
- [ ] Pull a test secret from Python and/or PowerShell.

**Repo hygiene**
- [ ] `.gitignore` includes `__pycache__/`, `*.pyc`, `*.json` configs, `.env`.
- [ ] No tokens, configs, or secret values committed.
- [ ] Replace `RecordUID` placeholders with real UIDs in your own scripts.
