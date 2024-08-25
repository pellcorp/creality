#!/usr/bin/env python3

#
# https://github.com/pyscaffold/configupdater
#

import io, os
from configupdater import ConfigUpdater
import argparse


def main():
    parser = argparse.ArgumentParser(description='Pellcorp Config Overrides')
    parser.add_argument("-o", "--original", type=str, required=True)
    parser.add_argument("-u", "--updated", type=str, required=True)
    parser.add_argument("-v", "--overrides", type=str, required=True)
    args = parser.parse_args()

    if not os.path.exists(args.original):
        raise Exception(f"Config File {args.original} not found")
    if not os.path.exists(args.updated):
       raise Exception(f"Config File {args.updated} not found")

    original = ConfigUpdater(strict=False, allow_no_value=True, space_around_delimiters=False, delimiters=(":", "="))
    with open(args.original, 'r') as file:
        original.read_file(file)
    
    updated = ConfigUpdater(strict=False, allow_no_value=True, space_around_delimiters=False, delimiters=(":", "="))
    with open(args.updated, 'r') as file:
        updated.read_file(file)

    overrides = ConfigUpdater(strict=False, allow_no_value=True, space_around_delimiters=False, delimiters=(":", "="))
    
    update_overrides = False
    printer_cfg = 'printer.cfg' == os.path.basename(args.original)
    moonraker_conf = 'moonraker.conf' == os.path.basename(args.original)

    # support deleting includes only
    for section_name in original.sections():
        if 'include' in section_name and section_name not in updated.sections():
            if len(overrides.sections()) > 0:
                overrides[overrides.sections()[-1]].add_after.space().section(section_name)
            else:
                overrides.add_section(section_name)
            overrides[section_name]['__action__'] = ' DELETED'
            update_overrides = True

    for section_name in updated.sections():
        # so for printer.cfg and moonraker.conf a new section can be saved, but it can't be a gcode macro
        if 'gcode_macro' not in section_name and (printer_cfg or moonraker_conf):
            if section_name not in original.sections():
                new_section = updated.get_section(section_name, None)
                if len(overrides.sections()) > 0:
                    overrides[overrides.sections()[-1]].add_after.space().section(section_name)
                else:
                    overrides.add_section(section_name)

                for key in new_section.keys():
                    value = new_section.get(key, None)
                    if len(value.lines) > 1:
                        lines = value.lines
                        lines[0] = '\n'
                        overrides[section_name][key] = ''
                        overrides[section_name][key].set_values(lines, indent='', separator='')
                    else:
                        overrides[section_name][key] = f' {value.value.strip()}'
                update_overrides = True

    # any deleted entries
    for section_name in updated.sections():
        original_section = original.get_section(section_name, None)
        updated_section = updated.get_section(section_name, None)
        if original_section and updated_section:
            for key in original_section.keys():
                if key not in updated_section:
                    if not overrides.has_section(section_name):
                        if len(overrides.sections()) > 0:
                            overrides[overrides.sections()[-1]].add_after.space().section(section_name)
                        else:
                            overrides.add_section(section_name)
                    overrides[section_name][key] = ' __DELETED__'
                    update_overrides = True

            # new or updated values
            for key in updated_section.keys():
                original_value = original_section.get(key, None)
                updated_value = updated_section.get(key, None)

                if key != 'gcode':
                    if (not original_value and updated_value and updated_value.value) or (original_value and original_value.value and updated_value and updated_value.value and original_value.value != updated_value.value):
                        if not overrides.has_section(section_name):
                            if len(overrides.sections()) > 0:
                                overrides[overrides.sections()[-1]].add_after.space().section(section_name)
                            else:
                                overrides.add_section(section_name)

                        # this will mostly be used for gcode macros and values
                        if len(updated_value.lines) > 1:
                            lines = updated_value.lines
                            lines[0] = '\n'
                            overrides[section_name][key] = ''
                            overrides[section_name][key].set_values(lines, indent='', separator='')
                        else:
                            overrides[section_name][key] = f' {updated_value.value.strip()}'
                        update_overrides = True

    if update_overrides:
        print(f"Saving overrides to {args.overrides} ...")
        with open(args.overrides, 'w') as file:
            overrides.write(file)
            

if __name__ == '__main__':
    main()
