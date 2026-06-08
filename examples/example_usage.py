"""Example: pulling secrets from Keeper instead of hard-coding them.

Prerequisite: run setup\\Setup-KSM.ps1 once on this device.

Run from the repo root:
    python examples\\example_usage.py
"""

import os
import sys

# Make the `ksm` package importable when running this file directly.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ksm import get_value, get_field, get_secret_by_title


def main():
    # --- Option A: Keeper Notation (most precise; UID never changes) ---------
    # Format: <RecordUID>/field/<fieldName>  or  /custom_field/<label>
    # db_password = get_value("EG6KdJaaLG7esRZbMnfbFA/field/password")
    # api_key     = get_value("EG6KdJaaLG7esRZbMnfbFA/custom_field/API Key")

    # --- Option B: look up by record title -----------------------------------
    # db_user     = get_field("Prod Database", "login")
    # db_password = get_field("Prod Database", "password")
    # api_key     = get_field("Payments API", "API Key", custom=True)

    # --- Option C: the whole record ------------------------------------------
    # record = get_secret_by_title("Prod Database")
    # print(record.title, record.uid)

    # Safe demo that doesn't assume any specific record exists: list what this
    # device can see.
    from ksm import get_secrets
    records = get_secrets()
    print(f"This device can access {len(records)} Keeper record(s):")
    for r in records:
        print(f"  - {r.title}  (uid={r.uid})")


if __name__ == "__main__":
    main()
