"""Tiny CLI bridge so non-Python callers (PowerShell, batch, etc.) can read a
single secret value by Keeper Notation.

Usage:
    python ksm/get.py "<RecordUID>/field/password"

Prints the value to stdout (no trailing newline). Exits non-zero with an error
on stderr if the lookup fails or the device isn't set up.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ksm import get_value


def main():
    notation = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("KSM_NOTATION", "")
    notation = notation.strip()
    if not notation:
        print("ERROR: no Keeper Notation provided.", file=sys.stderr)
        return 1
    try:
        value = get_value(notation)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    if value is None:
        print(f"ERROR: no value found for notation: {notation}", file=sys.stderr)
        return 1
    sys.stdout.write(str(value))
    return 0


if __name__ == "__main__":
    sys.exit(main())
