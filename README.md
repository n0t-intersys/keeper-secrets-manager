# Keeper Secrets Manager (KSM) for the Team

Pull secrets from Keeper at runtime instead of hard-coding them in source,
config files, or committed environment variables.

- **Platform:** Windows (PowerShell)
- **Language:** Python (`keeper-secrets-manager-core`), plus a PowerShell helper
- **Credential delivery:** one personal one-time token per developer/device
- **Where config lives:** Windows Credential Manager (no secrets/config on disk)

## Quick start

**Developer (once per device):**
```powershell
.\setup\Setup-KSM.ps1
```
Paste your one-time token when prompted. That's it.

**Use a secret in Python:**
```python
from ksm import get_value
pw = get_value("RecordUID/field/password")
```

**Use a secret in PowerShell:**
```powershell
Import-Module ".\ksm\Ksm.psm1" -Force
$pw = Get-KsmValue "RecordUID/field/password"
```

## Full documentation

See **[docs/TEAM-DEPLOYMENT-GUIDE.md](docs/TEAM-DEPLOYMENT-GUIDE.md)** for the
complete guide: admin token issuance, developer onboarding, notation reference,
security practices, rotation/revocation, and troubleshooting.

## Repo layout

| Path | Purpose |
|------|---------|
| `setup/Setup-KSM.ps1` | One-time developer onboarding (run once per device). |
| `ksm/ksm_client.py`   | Python helper: `get_value`, `get_field`, `get_secret_by_title`. |
| `ksm/Ksm.psm1`        | PowerShell module: `Get-KsmValue`. |
| `ksm/bootstrap.py`    | Redeems token + stores config in Credential Manager. |
| `ksm/get.py`          | CLI bridge used by the PowerShell module. |
| `ksm/config_store.py` | Credential Manager service/key names. |
| `examples/`           | Runnable Python and PowerShell examples. |
| `requirements.txt`    | Python dependencies. |
