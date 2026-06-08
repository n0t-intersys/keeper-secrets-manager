"""Shared location/keys for where the redeemed KSM config is stored.

The config is kept as a base64 string inside the OS-native credential store
(Windows Credential Manager) via the `keyring` library. Nothing is written to
disk, so the SDK config never sits in a plaintext file on the device.
"""

KEYRING_SERVICE = "KeeperSecretsManager"
KEYRING_USERNAME = "ksm-config"
