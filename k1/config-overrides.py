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
    fan_control = 'fan_control.cfg' == os.path.basename(args.original)

    # only support deleting sections from printer.cfg for now
    for section_name in original.sections():
        if section_name not in updated.sections() and printer_cfg:
            if len(overrides.sections()) > 0:
                overrides[overrides.sections()[-1]].add_after.space().section(section_name)
            else:
                overrides.add_section(section_name)
            overrides[section_name]['__action__'] = ' DELETED'
            update_overrides = True

    for section_name in updated.sections():
        # so for printer.cfg, moonraker.conf or fan_control a new section can be saved, but it can't be a gcode macro
        # and we are ignoring a new scanner section in config overrides due to migrating to cartotouch.cfg
        if section_name != 'scanner' and 'gcode_macro' not in section_name and (printer_cfg or moonraker_conf or fan_control):
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

    for section_name in updated.sections():
        original_section = original.get_section(section_name, None)
        updated_section = updated.get_section(section_name, None)
        if original_section and updated_section:
            for key in original_section.keys():
                # cannot delete a section value unless its from printer.cfg
                if key not in updated_section and printer_cfg:
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

                # do not generate any overrides for scanner in printer.cfg because we are migrating to cartotouch.cfg
                if printer_cfg and section_name == 'scanner':
                    continue

                # no gcode macros or sensorless gcode overrides
                if ('gcode_macro' in section_name or section_name == 'homing_override') and key == 'gcode':
                    continue

                # disable all overrides for any gcode shell commands
                if 'gcode_shell_command' in section_name:
                    continue

                # the stream urls are updated by s96ipaddress service so ignore if they are different
                if 'webcam default' in section_name and (key == 'stream_url' or key == 'snapshot_url'):
                    continue

                # do not save the serial field
                if (section_name == 'scanner' or section_name == 'cartographer' or section_name == 'mcu eddy') and key == 'serial':
                    continue

                # do not add a new value that was missing from original unless this is for printer.cfg
                if not original_value and not printer_cfg:
                    continue

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
        print(f"INFO: Saving overrides to {args.overrides} ...")
        with open(args.overrides, 'w') as file:
            overrides.write(file)
            

if __name__ == '__main__':
    main()
