"""Generate a .env file by resolving Keeper notation from a template.

Reads a committed template (no secrets) and writes a real .env with values
pulled from Keeper Secrets Manager via the `ksm` helper.

Template line handling:
  # comment            -> copied through unchanged
  (blank line)         -> copied through unchanged
  VAR=keeper://<notation>  -> VAR="<secret resolved from Keeper>"
  VAR=<anything else>  -> copied through literally (non-secret config)

Notation examples (see docs): keeper://<RecordUID>/field/password
                              keeper://<RecordUID>/custom_field/API Key

Usage:
  python ksm/gen_env.py                         # .env.template -> .env
  python ksm/gen_env.py --template app.env.tmpl --out C:\\app\\.env
  python ksm/gen_env.py --force                 # overwrite an existing .env

SECURITY: the generated .env contains PLAINTEXT secrets. It must never be
committed (it's gitignored) and should not live in a cloud-synced folder
(OneDrive/Dropbox) — this tool refuses to write there unless --allow-cloud-sync.
"""

import argparse
import os
import sys

try:
    from ksm import get_value
except ImportError:
    # Allow running as a plain script without the editable install.
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from ksm import get_value

KEEPER_PREFIX = "keeper://"


def escape_value(value):
    """Double-quote a value and escape backslash, quote, CR and LF for .env."""
    v = (value.replace("\\", "\\\\")
              .replace('"', '\\"')
              .replace("\r", "\\r")
              .replace("\n", "\\n"))
    return f'"{v}"'


def is_cloud_synced(path):
    """True if path is inside a known OneDrive-synced folder."""
    ap = os.path.normcase(os.path.abspath(path))
    for env in ("OneDrive", "OneDriveCommercial", "OneDriveConsumer"):
        root = os.environ.get(env)
        if root and ap.startswith(os.path.normcase(os.path.abspath(root))):
            return True
    return os.sep + "onedrive" in ap or "onedrive -" in ap


def main():
    parser = argparse.ArgumentParser(description="Generate a .env from a Keeper-notation template.")
    parser.add_argument("--template", default=".env.template", help="template file (default: .env.template)")
    parser.add_argument("--out", default=".env", help="output .env path (default: .env)")
    parser.add_argument("--force", action="store_true", help="overwrite an existing output file")
    parser.add_argument("--allow-cloud-sync", action="store_true",
                        help="permit writing into a OneDrive/cloud-synced folder (NOT recommended)")
    args = parser.parse_args()

    if not os.path.exists(args.template):
        print(f"ERROR: template not found: {args.template}", file=sys.stderr)
        return 2

    out_abs = os.path.abspath(args.out)
    if os.path.exists(out_abs) and not args.force:
        print(f"ERROR: {args.out} already exists. Use --force to overwrite.", file=sys.stderr)
        return 2
    if is_cloud_synced(out_abs) and not args.allow_cloud_sync:
        print(f"ERROR: {args.out}\n"
              f"       is inside a cloud-synced (OneDrive) folder. Writing plaintext secrets\n"
              f"       there would upload them to the cloud. Pick a path outside OneDrive, or\n"
              f"       pass --allow-cloud-sync to override (not recommended).", file=sys.stderr)
        return 3

    out_lines = []
    resolved = 0
    with open(args.template, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in line:
                out_lines.append(line)
                continue
            key, val = line.split("=", 1)
            val = val.strip()
            if val.startswith(KEEPER_PREFIX):
                notation = val[len(KEEPER_PREFIX):].strip()
                secret = get_value(notation)
                if secret is None:
                    print(f"ERROR: no Keeper value for {key.strip()} ({notation})", file=sys.stderr)
                    return 4
                out_lines.append(f"{key.strip()}={escape_value(str(secret))}")
                resolved += 1
            else:
                out_lines.append(line)

    with open(out_abs, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out_lines) + "\n")

    print(f"Wrote {args.out} ({resolved} secret(s) resolved from Keeper).")
    print("Reminder: never commit this file; it contains plaintext secrets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
