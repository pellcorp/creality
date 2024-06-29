#!/usr/bin/env python3

#
# https://github.com/pyscaffold/configupdater
#

import optparse, io, os
from configupdater import ConfigUpdater


def main():
    opts = optparse.OptionParser("Config Helper")
    opts.add_option("", "--original", dest="original")
    opts.add_option("", "--updated", dest="updated")
    opts.add_option("", "--overrides", dest="overrides")
    options, _ = opts.parse_args()

    if not os.path.exists(options.original):
        raise Exception(f"Config File {options.original} not found")
    if not os.path.exists(options.updated):
       raise Exception(f"Config File {options.updated} not found")
    if os.path.exists(options.overrides):
        raise Exception(f"Config File {options.overrides} exists")

    original = ConfigUpdater(strict = False, allow_no_value = True, space_around_delimiters = False, delimiters = ':')
    with open(options.original, 'r') as file:
        original.read_file(file)
    
    updated = ConfigUpdater(strict = False, allow_no_value = True, space_around_delimiters = False, delimiters = ':')
    with open(options.updated, 'r') as file:
       updated.read_file(file)

    overrides = ConfigUpdater(strict = False, allow_no_value = True, space_around_delimiters = False, delimiters = ':')
    
    update_overrides = False

    # ok first take care of deleted sections
    for section_name in original.sections():
        if 'gcode_macro' not in section_name:
            if section_name not in updated.sections():
                if len(overrides.sections()) > 0:
                    overrides[overrides.sections()[-1]].add_after.space().section(section_name)
                else:
                    overrides.add_section(section_name)
                overrides[section_name]['__action__'] = ' DELETED'
                update_overrides = True

    # now new sections
    for section_name in updated.sections():
        # trying to handle gcode macros is problematic will just skip them for now
        if 'gcode_macro' not in section_name:
            if section_name not in original.sections():
                new_section = updated.get_section(section_name, None)
                if len(overrides.sections()) > 0:
                    overrides[overrides.sections()[-1]].add_after.space().section(new_section.detach())
                else:
                    overrides.add_section(new_section.detach())
                update_overrides = True

    # now lets figure out any deleted entries
    for section_name in updated.sections():
        # trying to handle gcode macros is problematic will just skip them for now
        if 'gcode_macro' not in section_name:
            original_section = original.get_section(section_name, None)
            updated_section = updated.get_section(section_name, None)
            if original_section and updated_section:
                # keys removed from original
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

                    if (not original_value and updated_value) or (original_value and updated_value and original_value.value != updated_value.value):
                        if not overrides.has_section(section_name):
                            if len(overrides.sections()) > 0:
                                overrides[overrides.sections()[-1]].add_after.space().section(section_name)
                            else:
                                overrides.add_section(section_name)
                        overrides[section_name][key] = f' {updated_value.value.strip()}'
                        update_overrides = True

                    
    if update_overrides:
        print(f"Saving overrides for {options.original} ...")
        with open(options.overrides, 'w') as file:
            overrides.write(file)
            

if __name__ == '__main__':
    main()
