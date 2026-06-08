"""Team-wide helper for reading secrets from Keeper Secrets Manager.

Import this in your application code instead of hard-coding credentials:

    from ksm import get_value

    db_password = get_value("MyDatabaseRecordUID/field/password")

The KSM config is loaded from Windows Credential Manager (populated once by
Setup-KSM.ps1). The SecretsManager client is created lazily and cached, so
repeated calls in the same process reuse one client.
"""

import base64

import keyring
from keeper_secrets_manager_core import SecretsManager
from keeper_secrets_manager_core.storage import InMemoryKeyValueStorage

try:
    from .config_store import KEYRING_SERVICE, KEYRING_USERNAME
except ImportError:  # allow running as a plain script, not just as a package
    from config_store import KEYRING_SERVICE, KEYRING_USERNAME

_manager = None


def _get_manager():
    global _manager
    if _manager is None:
        config_b64 = keyring.get_password(KEYRING_SERVICE, KEYRING_USERNAME)
        if not config_b64:
            raise RuntimeError(
                "Keeper Secrets Manager is not initialized on this device. "
                "Run setup\\Setup-KSM.ps1 first."
            )
        config_json = base64.b64decode(config_b64).decode("utf-8")
        _manager = SecretsManager(config=InMemoryKeyValueStorage(config_json))
    return _manager


def get_value(notation):
    """Return a single field value using Keeper Notation.

    Examples:
        get_value("EG6KdJaaLG7esRZbMnfbFA/field/password")
        get_value("EG6KdJaaLG7esRZbMnfbFA/custom_field/API Key")
    """
    result = _get_manager().get_notation(notation)
    if isinstance(result, list):
        return result[0] if result else None
    return result


def get_field(title, field_name, custom=False):
    """Return a field value from the first record matching `title`.

    Set custom=True to read a custom field (matched by its label).
    """
    secret = get_secret_by_title(title)
    if secret is None:
        raise KeyError(f"No Keeper record found with title: {title!r}")
    if custom:
        return secret.custom_field(field_name, single=True)
    return secret.field(field_name, single=True)


def get_secret_by_title(title):
    """Return the first record (KeeperRecord) matching the given title."""
    return _get_manager().get_secret_by_title(title)


def get_secrets(uids=None):
    """Return all records the application has access to, or only the given UIDs."""
    return _get_manager().get_secrets(uids=uids)
