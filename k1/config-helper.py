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


# so return the first section which is not a include
def _first_section(updater):
    first_section=None
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


def main():
    opts = optparse.OptionParser("Config Helper")
    opts.add_option("", "--file", dest="config_file", default=f'{PRINTER_CONFIG_DIR}/printer.cfg')
    opts.add_option("", "--output", dest="output")
    opts.add_option("", "--remove-section", dest="remove_section", nargs=1, type="string")
    opts.add_option("", "--remove-section-entry", dest="remove_section_entry", nargs=2, type="string")
    opts.add_option("", "--replace-section-entry", dest="replace_section_entry", nargs=3, type="string")
    opts.add_option("", "--remove-include", dest="remove_include", nargs=1, type="string")
    opts.add_option("", "--add-include", dest="add_include", nargs=1, type="string")
    options, _ = opts.parse_args()

    if os.path.exists(options.config_file):
        config_file = options.config_file
    elif os.path.exists(f"{PRINTER_CONFIG_DIR}/{options.config_file}"):
        config_file = f"{PRINTER_CONFIG_DIR}/{options.config_file}"
    elif os.path.exists(f"{os.environ['HOME']}/{options.config_file}"): # mostly for local testing
        config_file = f"{os.environ['HOME']}/{options.config_file}"
    else:
        raise Exception(f"Config File {options.config_file} not found")

    updater = ConfigUpdater(strict = False, allow_no_value = True, space_around_delimiters = False, delimiters = ':')
    with open(config_file, 'r') as file:
        updater.read_file(file)

    updated=False
    if options.remove_section:
        updated = remove_section(updater, options.remove_section)
    elif options.remove_section_entry:
        updated = remove_section_value(updater, options.remove_section_entry[0], options.remove_section_entry[1])
    elif options.replace_section_entry:
        updated = replace_section_value(updater, options.replace_section_entry[0], options.replace_section_entry[1], options.replace_section_entry[2])
    elif options.remove_include:
        updated = remove_include(updater, options.remove_include)
    elif options.add_include:
        updated = add_include(updater, options.add_include)
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
