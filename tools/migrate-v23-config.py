#!/usr/bin/env python3
"""Migrate the former PRTouch integration names, preserving configuration values."""
import argparse
import os
from pathlib import Path
import re
import shutil
import tempfile


def renamed(text):
    headers = re.findall(
        r"(?m)^\s*(#\*#\s*)?\[\s*(prtouch_v3|load_cell_v23)\s*\]\s*(?:[;#].*)?$",
        text,
    )
    for saved in (False, True):
        names = {name for prefix, name in headers if bool(prefix) == saved}
        if len(names) > 1:
            raise ValueError("both old and new V23 sections exist; resolve them before migration")
    if "[include prtouch_v3.cfg]" in text and "[include loadcells_v23.cfg]" in text:
        raise ValueError("both old and new V23 includes exist; resolve them before migration")
    text = text.replace("prtouch_v3.cfg", "loadcells_v23.cfg")
    text = re.sub(r"\bprtouch_v3\b", "load_cell_v23", text)
    text = text.replace("PRTOUCH_", "BED_LOAD_CELL_")
    return text.replace("prtouch_accept_", "v23_accept_")


def migrate(directories, backup_dir):
    plan = []
    for directory in directories:
        for path in sorted(Path(directory).glob("*")):
            if not path.is_file() or path.suffix not in (".cfg", ".conf", ".save_config"):
                continue
            before = path.read_bytes()
            after = renamed(before.decode()).encode()
            target = path.with_name("loadcells_v23.cfg") if path.name == "prtouch_v3.cfg" else path
            if before == after and target == path:
                continue
            if path.is_symlink() or target.is_symlink():
                raise ValueError("refusing to replace a configuration symlink: %s" % path)
            if target != path and target.exists() and target.read_bytes() != after:
                raise ValueError("different old and new V23 files exist: %s" % path.parent)
            plan.append((path, target, before, after))
    # Validate every input before writing any file, including saved offsets.
    for path, target, before, after in plan:
        if path.read_bytes() != before:
            raise ValueError("configuration changed during migration: %s" % path)
    for path, target, before, after in plan:
        backup = Path(backup_dir) / str(path.resolve()).lstrip(os.sep)
        backup.parent.mkdir(parents=True, exist_ok=True)
        if not backup.exists():
            shutil.copy2(path, backup)
        descriptor, temporary = tempfile.mkstemp(prefix=".v23-rename-", dir=str(target.parent))
        try:
            with os.fdopen(descriptor, "wb") as output:
                output.write(after)
            shutil.copymode(path, temporary)
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        if target != path:
            path.unlink()
    return len(plan)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", action="append", required=True,
                        help="Configuration directory (repeat for overrides)")
    parser.add_argument("--backup-dir", required=True)
    args = parser.parse_args()
    try:
        count = migrate(args.config_dir, args.backup_dir)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, "V23 naming migration failed: %s\n" % error)
    print("V23 naming migration: %d file(s) updated" % count)


if __name__ == "__main__":
    main()
