# KSM device setup — successful run (reference)

This documents a verified, working run of `setup\Setup-KSM.ps1` on a Windows
device. Use it as the "known good" output when onboarding teammates.

## Console output (transcribed from screenshot)

```
Paste your Keeper one-time access token (e.g. US:XXXX...): ********************************
Redeeming token and storing config in Windows Credential Manager ...
KSM config stored in Windows Credential Manager.
Verifying access ...
Success: this device can access 2 record(s).

Done. Your team's code can now read secrets without the token.
See examples\example_usage.py for how to use the helper.
```

## What this confirms
- Python + dependencies (`keeper-secrets-manager-core`, `keyring`) installed.
- One-time token redeemed successfully (single-use; now spent).
- Derived config saved to Windows Credential Manager (no file on disk).
- Device can reach the vault and read the records granted to the Application
  (2 records in this run).

## Screenshot
Save the original screenshot next to this file as `setup-success.png` for the
visual record.
```
docs/
├─ setup-success.md   <- this file
└─ setup-success.png  <- drop the screenshot here
```
