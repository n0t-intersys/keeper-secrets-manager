"""One-time device setup: redeem a Keeper one-time access token and store the
resulting KSM config in Windows Credential Manager.

Run via Setup-KSM.ps1. The token is read from the KSM_TOKEN environment
variable so it never appears in the process command line / shell history.

The token is single-use: once redeemed it cannot be used again. The config
produced from it is what every later call uses, so we persist that config
(base64-encoded) into the OS credential store.
"""

import base64
import os
import sys
import tempfile

import keyring
from keeper_secrets_manager_core import SecretsManager
from keeper_secrets_manager_core.storage import FileKeyValueStorage

from config_store import KEYRING_SERVICE, KEYRING_USERNAME


def redeem(token):
    # Redeem the token into a temp config file. FileKeyValueStorage writes the
    # canonical config JSON that the SDK can later reload from a base64 string.
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False, dir=os.path.expanduser("~")
    )
    tmp.close()
    try:
        sm = SecretsManager(token=token, config=FileKeyValueStorage(tmp.name))
        # At least one read is required to bind the token and populate config.
        sm.get_secrets()

        with open(tmp.name, "r", encoding="utf-8") as fh:
            config_json = fh.read()
    finally:
        try:
            os.remove(tmp.name)
        except OSError:
            pass

    config_b64 = base64.b64encode(config_json.encode("utf-8")).decode("ascii")
    keyring.set_password(KEYRING_SERVICE, KEYRING_USERNAME, config_b64)


def verify():
    """Load the stored config and confirm the device can reach the vault."""
    from ksm_client import get_secrets

    records = get_secrets()
    print(f"Success: this device can access {len(records)} record(s).")


def remove():
    """Delete the stored KSM config from Windows Credential Manager.

    Idempotent: reports success even if nothing was stored.
    """
    existing = keyring.get_password(KEYRING_SERVICE, KEYRING_USERNAME)
    if existing is None:
        print("Nothing to remove: no KSM config found on this device.")
        return
    keyring.delete_password(KEYRING_SERVICE, KEYRING_USERNAME)
    print("KSM config removed from Windows Credential Manager.")


def main():
    if "--verify" in sys.argv[1:]:
        try:
            verify()
        except Exception as exc:
            print(f"ERROR: verification failed: {exc}", file=sys.stderr)
            return 1
        return 0

    if "--remove" in sys.argv[1:]:
        try:
            remove()
        except Exception as exc:
            print(f"ERROR: failed to remove config: {exc}", file=sys.stderr)
            return 1
        return 0

    token = os.environ.get("KSM_TOKEN", "").strip()
    if not token:
        print("ERROR: KSM_TOKEN environment variable is not set.", file=sys.stderr)
        return 1

    try:
        redeem(token)
    except Exception as exc:  # surface the real reason to the setup script
        print(f"ERROR: failed to redeem token: {exc}", file=sys.stderr)
        return 1

    print("KSM config stored in Windows Credential Manager.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
