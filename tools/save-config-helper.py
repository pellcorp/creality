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
                section_name = stripped_line[4:]
                print(f"INFO: Removing {section_name} section ...")
                skipping = True
                updated = True
                continue

            if skipping and line.startswith("#*# ["):
                skipping = False

            if not skipping:
                new_content.append(line)

        if updated:
            # cleanup the bottom of the file, will also remove save config header if we removed all the save config sections
            cleaned_up = False
            while new_content:
                last = new_content[-1].strip()
                if last == "#*#" or "SAVE_CONFIG" in last or "DO NOT EDIT THIS BLOCK OR BELOW" in last or last == "":
                    cleaned_up = True
                    new_content.pop()
                else:
                    break

            # just for neatness re-add a new line at the end
            if cleaned_up:
                new_content.append("\n")

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
    parser.add_argument("--file", default=f"{PRINTER_CONFIG_DIR}/printer.cfg", help="Path to printer.cfg")
    parser.add_argument("--remove-section", nargs='+', required=True, help="Space-separated list of sections to remove")

    args = parser.parse_args()

    editor = SaveConfigHelper(args.file)
    changed = False
    for section in args.remove_section:
        if editor.remove_section(section):
            changed = True
    if changed:
        editor.save()
        sys.exit(0)
    else: # no changes made give caller a hint
        sys.exit(1)
