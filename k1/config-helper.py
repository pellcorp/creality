#!/usr/bin/env python3

#
# https://github.com/pyscaffold/configupdater
#

PRINTER_CONFIG_DIR = "/usr/data/printer_data/config/"

import optparse, io, os
from configupdater import ConfigUpdater


def remove_section_value(updater, section_name, key):
    if updater.has_option(section_name, key):
        updater.remove_option(section_name, key)
        return True
    return False


def get_section_value(updater, section_name, key):
    if updater.has_section(section_name):
        section = updater.get_section(section_name, None)
        if section:
            current_value = section.get(key, None)
            if current_value:
                return current_value.value
    return None


# currently we do not support adding a whole new mulitline value
def replace_section_multiline_value(updater, section_name, key, lines):
    if updater.has_section(section_name):
        section = updater.get_section(section_name, None)
        if section:
            current_value = section.get(key, None)
            if current_value:
                if key in section:
                    if current_value.lines != lines:
                        lines[0] = '\n'
                        section[key] = ''
                        section[key].set_values(lines, indent='', separator='')
                        return True
    return False


def replace_section_value(updater, section_name, key, value):
    if updater.has_section(section_name):
        section = updater.get_section(section_name, None)
        if section:
            current_value = section.get(key, None)
            if current_value:
                if key in section and current_value.value != value:
                    # note there is a single space prefixed which seems to
                    # be the general format of the creality printer config files
                    section[key] = f' {value.strip()}'
                    return True
            else:
                section.last_block.add_before.option(key, f' {value.strip()}')
                return True
    return False


# the section is everything in the square brackets
def remove_section(updater, section):
    if updater.has_section(section):
        updater.remove_section(section)
        return True
    return False


# special case currently for fan_control.cfg to add additional
# config sections before the gcode
def _last_section(updater):
    last_section = None
    for section in updater.sections():
        if not section.startswith("gcode_macro "):
            last_section = section
        else:
            break
    return last_section


# so return the first section which is not a include
def _first_section(updater):
    first_section = None
    for section in updater.sections():
        if not section.startswith("include "):
            first_section = section
            break
    return first_section


def remove_include(updater, include):
    if updater.has_section(f"include {include}"):
        updater.remove_section(f"include {include}")
        return True
    return False


def add_include(updater, include):
    if not updater.has_section(f"include {include}"):
        first_section = _first_section(updater)
        updater[first_section].add_before.section(f"include {include}").space(1)
        return True
    return False


def add_section(updater, section_name):
    if not updater.has_section(section_name):
        last_section = _last_section(updater)
        if last_section:
            updater[last_section].add_before.section(section_name).space()
        else: # file is basically empty
            updater.add_section(section_name)
    return True


def override_cfg(updater, override_cfg_file):
    overrides = ConfigUpdater(strict = False, allow_no_value = True, space_around_delimiters = False, delimiters = ':')
    updated = False
    with open(override_cfg_file, 'r') as file:
        overrides.read_file(file)
        for section_name in overrides.sections():
            section = overrides.get_section(section_name, None)
            section_action = section.get('__action__', None)
            if section_action and section_action.value == 'DELETED':
                if updater.has_section(section_name):
                    if remove_section(updater, section_name):
                        updated = True
            elif updater.has_section(section_name):
                for entry in section:
                    value = section.get(entry, None)
                    if value and value.value == '__DELETED__' and remove_section_value(updater, section_name, entry):
                        updated = True
                    elif value and len(value.lines) > 1 and replace_section_multiline_value(updater, section_name, entry, value.lines):
                        updated = True
                    elif value and len(value.lines) == 1 and replace_section_value(updater, section_name, entry, value.value):
                        updated = True
            elif 'include ' in section_name: # handle an include being added
                include = section_name.replace('include ', '')
                if add_include(updater, include):
                    updated = True
            elif 'gcode_macro' not in section_name: # no new gcode macros
                new_section = overrides.get_section(section_name, None)
                if new_section:
                    last_section = _last_section(updater)
                    if last_section:
                        updater[last_section].add_before.section(new_section.detach()).space()
                    else: # file is basically empty
                        updater.add_section(new_section.detach())
                    updated = True
    return updated


def main():
    opts = optparse.OptionParser("Config Helper")
    opts.add_option("", "--file", dest="config_file", default=f'{PRINTER_CONFIG_DIR}/printer.cfg')
    opts.add_option("", "--output", dest="output")
    opts.add_option("", "--remove-section", dest="remove_section", nargs=1, type="string")
    opts.add_option("", "--remove-section-entry", dest="remove_section_entry", nargs=2, type="string")
    opts.add_option("", "--get-section-entry", dest="get_section_entry", nargs=2, type="string")
    opts.add_option("", "--replace-section-entry", dest="replace_section_entry", nargs=3, type="string")
    opts.add_option("", "--remove-include", dest="remove_include", nargs=1, type="string")
    opts.add_option("", "--add-include", dest="add_include", nargs=1, type="string")
    opts.add_option("", "--add-section", dest="add_section", nargs=1, type="string")
    opts.add_option("", "--overrides", dest="overrides", nargs=1, type="string")
    options, _ = opts.parse_args()

    if os.path.exists(options.config_file):
        config_file = options.config_file
    elif os.path.exists(f"{PRINTER_CONFIG_DIR}/{options.config_file}"):
        config_file = f"{PRINTER_CONFIG_DIR}/{options.config_file}"
    elif os.path.exists(f"{os.environ['HOME']}/{options.config_file}"): # mostly for local testing
        config_file = f"{os.environ['HOME']}/{options.config_file}"
    else:
        raise Exception(f"Config File {options.config_file} not found")

    updater = ConfigUpdater(strict=False, allow_no_value=True, space_around_delimiters=False, delimiters=(":", "="))
    with open(config_file, 'r') as file:
        updater.read_file(file)

    updated=False
    if options.remove_section:
        updated = remove_section(updater, options.remove_section)
    elif options.remove_section_entry:
        updated = remove_section_value(updater, options.remove_section_entry[0], options.remove_section_entry[1])
    elif options.get_section_entry:
        value = get_section_value(updater, options.get_section_entry[0], options.get_section_entry[1])
        if value:
            print(value)
    elif options.replace_section_entry:
        updated = replace_section_value(updater, options.replace_section_entry[0], options.replace_section_entry[1], options.replace_section_entry[2])
    elif options.remove_include:
        updated = remove_include(updater, options.remove_include)
    elif options.add_include:
        updated = add_include(updater, options.add_include)
    elif options.add_section:
        updated = add_section(updater, options.add_section)
    elif options.overrides:
        if os.path.exists(options.overrides):
            updated = override_cfg(updater, options.overrides)
        else:
            raise Exception(f"Overrides Config File {options.overrides} not found")
    else:
        print(f"Invalid action")

    if updated:
        if options.output:
            with open(options.output, 'w') as file:
                updater.write(file)
        else:
            with open(config_file, 'w') as file:
                updater.write(file)
    elif options.output:
        with open(options.output, 'w') as file:
                updater.write(file)
        

if __name__ == '__main__':
    main()
