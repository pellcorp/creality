#!/usr/bin/env python3

#
# https://github.com/pyscaffold/configupdater
#

import optparse, io, os, sys
import os.path
from configupdater import ConfigUpdater

if os.path.isdir("/usr/data/printer_data/config"):
    PRINTER_CONFIG_DIR = "/usr/data/printer_data/config"
else:
    PRINTER_CONFIG_DIR = f"{os.environ['HOME']}/printer_data/config"

def remove_section_value(updater, section_name, key):
    if updater.has_section(section_name):
        section = updater.get_section(section_name, None)
        if section:
            current_value = section.get(key, None)
            if current_value:
                del section[key]
                if current_value.lines == 1:
                    section.last_block.add_before.comment(f"{current_value}")
                else:
                    for _, line in enumerate(current_value.lines):
                        section.last_block.add_before.comment(f"{line}")
                return True
    return False


def get_section_value(updater, section_name, key):
    if updater.has_section(section_name):
        section = updater.get_section(section_name, None)
        if section:
            current_value = section.get(key, None)
            if current_value:
                value = current_value.value
                if '#' in value:
                    return value.split('#', 1)[0].strip()
                elif ';' in value:
                    return value.split(';', 1)[0].strip()
                else:
                    return value.strip()
    return None


# ignore the first element in the array
def __lines_differ(current_lines, new_lines):
    if len(current_lines) != len(new_lines):
        return True
    for index, line in enumerate(current_lines):
        if index > 0 and line != new_lines[index]:
            return True
    return False


def replace_section_multiline_value(updater, section_name, key, lines):
    if updater.has_section(section_name):
        section = updater.get_section(section_name, None)
        if section:
            current_value = section.get(key, None)
            if not current_value or __lines_differ(current_value.lines, lines):
                lines[0] = '\n'
                lines[-1] = lines[-1].rstrip()
                if key not in section:
                    section.last_block.add_before.option(key, '')
                section[key].set_values(lines, indent='', separator='', prepend_newline=False)
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


def _last_include(updater):
    last_include = None
    for section in updater.sections():
        if section.startswith("include "):
            last_include = section
    return last_include


def remove_include(updater, include):
    if updater.has_section(f"include {include}"):
        updater.remove_section(f"include {include}")
        return True
    return False


def add_include(updater, include, printer_cfg=False):
    if not updater.has_section(f"include {include}"):
        first_section = _first_section(updater)
        if printer_cfg:
            updater[first_section].add_before.section(f"include {include}").space(1)
        else:
            last_include = _last_include(updater)
            if last_include:
                updater[last_include].add_after.section(f"include {include}").space(1)
            else:
                updater[first_section].add_before.section(f"include {include}").space(1)
        return True
    return False


def add_section(updater, section_name):
    if not updater.has_section(section_name):
        last_section = _last_section(updater)
        if last_section:
            updater[last_section].add_before.section(section_name).space()
        else:  # file is basically empty
            updater.add_section(section_name)
    return True


def override_cfg(updater, override_cfg_file,
                 allow_delete_section=True,
                 allow_delete_entry=True,
                 allow_new_section=True,
                 include_sections=None,
                 exclude_sections=None):
    overrides = ConfigUpdater(strict=False, allow_no_value=True, space_around_delimiters=False, delimiters=(':'))
    updated = False
    with open(override_cfg_file, 'r') as file:
        overrides.read_file(file)
        for section_name in overrides.sections():
            if (exclude_sections and section_name in exclude_sections) or (include_sections and section_name not in include_sections):
                continue

            section = overrides.get_section(section_name, None)
            section_action = section.get('__action__', None)
            if allow_delete_section and section_action and section_action.value == 'DELETED':
                if updater.has_section(section_name):
                    if remove_section(updater, section_name):
                        updated = True
            elif updater.has_section(section_name):
                for entry in section:
                    value = section.get(entry, None)
                    if value and value.value == '__DELETED__':
                        if allow_delete_entry and remove_section_value(updater, section_name, entry):
                            updated = True
                    elif value and len(value.lines) > 1:
                        if replace_section_multiline_value(updater, section_name, entry, value.lines):
                            updated = True
                    elif value and len(value.lines) == 1:
                        if replace_section_value(updater, section_name, entry, value.value):
                            updated = True
            elif 'include ' in section_name:
                include = section_name.replace('include ', '')
                if add_include(updater, include):
                    updated = True
            elif 'gcode_macro' not in section_name and 'gcode_shell_command' not in section_name and allow_new_section:
                new_section = overrides.get_section(section_name, None)
                if new_section:
                    last_section = _last_section(updater)
                    if last_section:
                        updater[last_section].add_before.section(new_section.detach()).space()
                    else:  # file is basically empty
                        updater.add_section(new_section.detach())
                    updated = True
    return updated


def main():
    exit_code = 0
    opts = optparse.OptionParser("Config Helper")
    opts.add_option("", "--file", dest="config_file", default=f'{PRINTER_CONFIG_DIR}/printer.cfg')
    opts.add_option("", "--output", dest="output")
    opts.add_option("", "--remove-section", dest="remove_section", nargs=1, type="string")
    opts.add_option("", "--remove-section-entry", dest="remove_section_entry", nargs=2, type="string")
    opts.add_option("", "--get-section-entry", dest="get_section_entry", nargs=2, type="string")
    # all these are for --get-section-entry only, saves me doing bash arithmetic
    opts.add_option("", "--integer", dest="integer", default=False, action='store_true')
    opts.add_option("", "--divisor", dest="divisor", nargs=1, type="int")
    opts.add_option("", "--minus", dest="minus", nargs=1, type="int")
    opts.add_option("", "--plus", dest="plus", nargs=1, type="int")
    opts.add_option("", "--replace-section-entry", dest="replace_section_entry", nargs=3, type="string")
    opts.add_option("", "--remove-include", dest="remove_include", nargs=1, type="string")
    opts.add_option("", "--add-include", dest="add_include", nargs=1, type="string")
    opts.add_option("", "--include-exists", dest="include_exists", nargs=1, type="string")
    opts.add_option("", "--section-exists", dest="section_exists", nargs=1, type="string")
    opts.add_option("", "--add-section", dest="add_section", nargs=1, type="string")
    opts.add_option("", "--ignore-missing", dest="ignore_missing", default=False, action='store_true')
    opts.add_option("", "--overrides", dest="overrides", nargs=1, type="string")
    opts.add_option("", "--exclude-sections", dest="exclude_sections", default=False)
    opts.add_option("", "--include-sections", dest="include_sections", default=False)
    opts.add_option("", "--patches", dest="patches", nargs=1, type="string")
    options, _ = opts.parse_args()

    if '/' in options.config_file and os.path.exists(options.config_file):
        config_file = options.config_file
    elif os.path.exists(f"{PRINTER_CONFIG_DIR}/{options.config_file}"):
        config_file = f"{PRINTER_CONFIG_DIR}/{options.config_file}"
    elif os.path.exists(f"{os.environ['HOME']}/{options.config_file}"):  # mostly for local testing
        config_file = f"{os.environ['HOME']}/{options.config_file}"
    elif options.ignore_missing:
        sys.exit(exit_code)
    else:
        raise Exception(f"Config File {options.config_file} not found")

    read_only = False
    updater = ConfigUpdater(strict=False, allow_no_value=True, space_around_delimiters=False, delimiters=(":", "="))

    # for reading config from printer.cfg.save_config it has to be read only
    if 'printer.cfg.save_config' == os.path.basename(config_file):
        read_only = True
        with open(config_file, 'r') as file:
            lines = ""
            for line in file:
                if "SAVE_CONFIG" in line or "DO NOT EDIT" in line:
                    line = line.replace("#*#", "#")
                else:
                    line = line.replace("#*#", "")
                lines += line
            updater.read_string(lines)
    else:
        with open(config_file, 'r') as file:
            updater.read_file(file)
    
    printer_cfg = 'printer.cfg' == os.path.basename(config_file)
    moonraker_conf = 'moonraker.conf' == os.path.basename(config_file)
    fan_control = 'fan_control.cfg' == os.path.basename(config_file)
    webcam_conf = 'webcam.conf' == os.path.basename(config_file)

    updated = False
    if options.remove_section:
        updated = remove_section(updater, options.remove_section)
    elif options.remove_section_entry:
        updated = remove_section_value(updater, options.remove_section_entry[0], options.remove_section_entry[1])
    elif options.get_section_entry:
        value = get_section_value(updater, options.get_section_entry[0], options.get_section_entry[1])
        if value:
            if options.integer or options.divisor or options.plus or options.minus:
                value = float(value)

            if options.divisor:
                value = value / options.divisor

            if options.plus:
                value = value + int(options.plus)

            if options.minus:
                value = value - int(options.minus)

            if options.integer:
                value = int(value)

            print(value)
        else:
            exit_code = 1
    elif options.include_exists:
        if updater.has_section(f"include {options.include_exists}"):
            exit_code = 0
        else:
            exit_code = 1
    elif options.section_exists:
        if updater.has_section(options.section_exists):
            exit_code = 0
        else:
            exit_code = 1
    elif options.replace_section_entry:
        updated = replace_section_value(updater, options.replace_section_entry[0], options.replace_section_entry[1], options.replace_section_entry[2])
    elif options.remove_include:
        updated = remove_include(updater, options.remove_include)
    elif options.add_include:
        updated = add_include(updater, options.add_include, printer_cfg=printer_cfg)
    elif options.add_section:
        updated = add_section(updater, options.add_section)
    elif options.patches:
        if os.path.exists(options.patches):
            updated = override_cfg(updater, options.patches, True, True, True)
        else:
            raise Exception(f"Patches Config File {options.overrides} not found")
    elif options.overrides:
        if os.path.exists(options.overrides):
            include_sections = options.include_sections.split(',') if options.include_sections else None
            exclude_sections = options.exclude_sections.split(',') if options.exclude_sections else None
            allow_delete_section = (printer_cfg or fan_control)
            allow_delete_entry = printer_cfg
            allow_new_section = (fan_control or printer_cfg or moonraker_conf or webcam_conf)
            updated = override_cfg(updater, options.overrides,
                                   allow_delete_section=allow_delete_section,
                                   allow_delete_entry=allow_delete_entry,
                                   allow_new_section=allow_new_section,
                                   include_sections=include_sections,
                                   exclude_sections=exclude_sections)
        else:
            raise Exception(f"Overrides Config File {options.overrides} not found")
    else:
        print(f"Invalid action")
        exit_code = 1

    if not read_only and updated:
        if options.output:
            with open(options.output, 'w') as file:
                updater.write(file)
        else:
            with open(config_file, 'w') as file:
                if options.overrides:
                    print(f"Applied overrides to {config_file}")
                elif options.patches:
                    print(f"Applied mount overrides to {config_file}")
                updater.write(file)
    elif not read_only and options.output:
        with open(options.output, 'w') as file:
            updater.write(file)

    sys.exit(exit_code)


if __name__ == '__main__':
    main()
