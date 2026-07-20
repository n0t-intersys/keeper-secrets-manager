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
| `ksm/gen_env.py` | Generate a `.env` from a template by resolving Keeper notation | Run when you need a `.env` |
| `ksm/Ksm.psm1` | PowerShell module exposing `Get-KsmValue` | Imported by .ps1 scripts |
| `.env.template` | Committed map of env vars → Keeper notation (no secrets) | Edit with your records |
| `examples/example_usage.py` | Python example | Reference |
| `examples/KeeperKSM-Example.ps1` | PowerShell example | Reference |
| `pyproject.toml` | Package metadata + deps; enables `pip install -e .` (import-anywhere) | Setup |
| `requirements.txt` | Python dependencies (mirrors pyproject) | Reference |

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
`Setup-KSM.ps1` installs the `ksm` package **editable** (`pip install -e .`), so
`import ksm` works from **any directory** and code edits take effect with no
reinstall. (If you skipped setup, run `pip install -e .` from the repo root.)
Then:
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

### 5d. Generate a `.env` file
For apps that read config from environment variables, generate a `.env` from a
committed template. `.env.template` maps env vars to Keeper notation (no secrets
in it); the generator resolves them:

```
# .env.template  (committed — references only)
APP_ENV=production                                   # literal, passed through
DB_USERNAME=keeper://RecordUID/field/login           # resolved from Keeper
DB_PASSWORD=keeper://RecordUID/field/password
API_KEY=keeper://RecordUID/custom_field/API Key
```

Generate the real `.env`:
```powershell
python ksm\gen_env.py                       # .env.template -> .env
python ksm\gen_env.py --out C:\myapp\.env   # write to your app's folder
python ksm\gen_env.py --force               # overwrite an existing .env
```
- Lines with `keeper://` are pulled from Keeper; everything else is copied
  literally. Resolved values are double-quoted/escaped.
- **The generated `.env` holds plaintext secrets.** It is gitignored — never
  commit it. Prefer regenerating it over storing it long-term.
- **Cloud-sync guard:** the generator **refuses** to write into a OneDrive
  (cloud-synced) folder, so your secrets aren't uploaded. Point `--out` at a
  local, non-synced path (e.g. your app directory). `--allow-cloud-sync`
  overrides this, but don't.

Consume the `.env`:
```python
# Python:  pip install python-dotenv
from dotenv import load_dotenv; import os
load_dotenv()                     # loads .env from cwd
db_pw = os.environ["DB_PASSWORD"]
```
```powershell
# PowerShell: load .env into the current session
Get-Content .env | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
    $k,$v = $_ -split '=',2
    Set-Item "Env:$($k.Trim())" ($v.Trim().Trim('"'))
}
```
```bash
# Docker: pass it straight in
docker run --env-file .env myimage
```

> Trade-off: a `.env` writes decrypted secrets to disk, which is a step down
> from the in-code `get_value()` path (secrets stay in Credential Manager and
> are fetched on demand). Use `.env` only when an app can't call the SDK
> directly; delete/regenerate rather than letting it linger.

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

### Revoking a client device (admin) — authoritative cutoff
Deleting the local config does **not** revoke access on its own. To guarantee a
device/developer can never pull secrets again, revoke its **client device** in
the Application. This is the step that actually matters for offboarding.

**Vault UI**
1. Open **Secrets Manager** → the **Application**.
2. Go to the **Devices** (client devices) list.
3. Find the device by its name/Short ID, click the **⋮ / remove** action, and
   confirm. Access is cut immediately; other devices are unaffected.

**Keeper Commander**
```
# 1. List the application's client devices to find the Client ID (Short ID):
secrets-manager app get <APPLICATION NAME|APP UID>

# 2a. Remove one device from a specific application:
secrets-manager client remove --app <APP UID> --client <CLIENT ID>

# 2b. Or revoke a client across ALL applications it belongs to:
secrets-manager client revoke --client <CLIENT ID>
```
- Clients are identified by their **Client ID / Short ID**, shown in the
  `app get` output.
- Add `--force` to skip the confirmation prompt in scripts.

> Offboarding order: revoke the client device first (cutoff), then have the
> device run `Remove-KSM.ps1` for local cleanup.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|--------|-------|-----|
| `Python was not found; run without arguments to install from the Microsoft Store` | Windows App-execution alias hijacks `python` | Settings → Apps → Advanced app settings → App execution aliases → turn OFF `python.exe`/`python3.exe`; reopen shell |
| `pip install failed` | Python/pip missing, proxy/SSL inspection, or `--user` conflict | `python -m ensurepip --upgrade`; behind proxy add `--proxy`; install without `--user` |
| `ModuleNotFoundError: No module named 'ksm'` | The editable install didn't run, or you're using a different Python than setup did | From the repo root: `python -m pip install -e .` (confirm it's the same `python` you run scripts with) |
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
