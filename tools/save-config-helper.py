#!/usr/bin/env python3

import argparse
import os
import sys

if os.path.isdir("/usr/data/printer_data/config"):
    PRINTER_CONFIG_DIR = "/usr/data/printer_data/config"
else:
    PRINTER_CONFIG_DIR = f"{os.environ['HOME']}/printer_data/config"

class SaveConfigHelper:
    def __init__(self, file_path):
        self.file_path = file_path
        self.lines = []
        if not os.path.exists(self.file_path):
            raise FileNotFoundError(f"Could not find {self.file_path}")
        with open(self.file_path, 'r') as f:
            self.lines = f.readlines()

    def remove_section(self, section_name):
        is_wildcard = section_name.endswith("*")
        if is_wildcard:
            section_name = section_name[:-1].strip()
            target = f"#*# [{section_name}"
        else:
            target = f"#*# [{section_name}]"

        new_content = []
        skipping = False
        updated = False

        for line in self.lines:
            stripped_line = line.strip()
            if (is_wildcard and stripped_line.startswith(target) and stripped_line.endswith("]")) or stripped_line == target:
                skipping = True
                updated = True
                continue

            if skipping and line.startswith("#*# ["):
                skipping = False

            if not skipping:
                new_content.append(line)

        if updated:
            self.lines = new_content
            return True
        else:
            return False

    def save(self):
        # Atomic-ish save: write to temp, then replace
        temp_file = self.file_path + ".tmp"
        with open(temp_file, 'w') as f:
            f.writelines(self.lines)
        os.replace(temp_file, self.file_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Delete specific sections from Klipper SAVE_CONFIG")
    parser.add_argument("--file", default="{PRINTER_CONFIG_DIR}/printer.cfg", help="Path to printer.cfg")
    parser.add_argument("--delete-section", nargs='+', required=True, help="Space-separated list of sections to remove")

    args = parser.parse_args()

    editor = SaveConfigHelper(args.file)
    changed = False
    for section in args.delete_section:
        if editor.remove_section(section):
            changed = True
    if changed:
        editor.save()
        sys.exit(0)
    else: # no changes made give caller a hint
        sys.exit(1)
