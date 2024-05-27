#!/bin/sh

#
# This is a best effort script to make changes to the printer.cfg and other cfg
# with the same [section], key:value syntax more friendly
#

function add_include() {
    local config_file="$1"
    local include="$2"

    # I don't want to rely on crafting the exact regex for 
    # grep so I walk the file to see if it exists    
    while IFS= read -r line; do
        if [ "$line" = "[include $include]" ]; then
            # already added
            return 0
        fi
    done < "$config_file"

    temp_file=/tmp/$$.cfg
    local changed=false
    local start=false
    while IFS= read -r line; do
        if [ "$changed" != "true" ]; then
            # we are looking for the start of non comments
            if echo "$line" | grep -q "^\[include"; then
                start=true
            elif [ "$start" = "true" ]; then
                changed=true
                echo "[include $include]" >> $temp_file
            fi
        fi
        echo "$line" >> $temp_file
    done < "$config_file"

    if [ "$changed" = "true" ]; then
        mv $temp_file "$config_file"
        return 0
    else
        rm $temp_file
        echo "ERROR: Failed to find insert point"
        return 1
    fi
}

function remove_include() {
    local config_file="$1"
    local include="$2"

    temp_file=/tmp/$$.cfg
    local found=false
    local changed=false
    while IFS= read -r line; do
        if [ "$changed" != "true" ]; then
            if [ "$line" = "[include $include]" ]; then
                changed=true
                continue;
            fi
        fi
        echo "$line" >> $temp_file
    done < "$config_file"

    if [ "$changed" = "true" ]; then
        mv $temp_file "$config_file"
    else
        rm $temp_file
    fi
    return 0
}

function remove_section_entry() {
    local config_file="$1"
    local section="$2"
    local entry="$3"

    temp_file=/tmp/$$.cfg
    local found_section=false
    local changed=false
    while IFS= read -r line; do
        if [ "$changed" != "true" ]; then
            if [ "$found_section" = "true" ]; then
                if echo "$line" | grep -q "^$entry:"; then
                    changed=true
                    # this is the entry we want to delete so just skip and then
                    continue
                fi
            elif echo "$line" | grep -q "^\[$section\]"; then
                found_section=true
            fi 2> /dev/null
        fi
        echo "$line" >> $temp_file
    done < "$config_file"

    if [ "$changed" = "true" ]; then
        mv $temp_file "$config_file"
    else
        rm $temp_file
        if [ "$found_section" != "true" ]; then
            echo "ERROR: Did not find section $section"
            return 1
        fi
        return 0
    fi
    return 0
}

function replace_section_entry() {
    local config_file="$1"
    local section="$2"
    local entry="$3"
    local value="$4"

    temp_file=/tmp/$$.cfg
    local found=false
    local changed=false
    local success=false
    while IFS= read -r line; do
        if [ "$success" != "true" ]; then
            if [ "$found" = "true" ]; then
                if echo "$line" | grep -q "^$entry:"; then
                    success=true

                    # only if the current value is different do we need to change it
                    current_value=$(echo "$line" | awk -F ':' '{print $2}' | tr -d '[:space:]')
                    if [ "$current_value" != "$value" ]; then
                        echo "$entry: $value" >> $temp_file
                        changed=true
                        continue
                    fi
                    
                fi
            elif echo "$line" | grep -q "^\[$section\]"; then
                found=true
            fi
        fi
        echo "$line" >> $temp_file
    done < "$config_file"

    if [ "$changed" = "true" ]; then
        mv $temp_file "$config_file"
    else
        # a missing section entry usually just means we already removed it
        rm $temp_file
        if [ "$success" != "true" ]; then
            echo "ERROR: Could not find section $section entry $entry"
            return 1
        fi
    fi
    return 0
}

function remove_section() {
    local config_file="$1"
    local section="$2"

    local found=false
    local changed=false
    temp_file=/tmp/$$.cfg
    while IFS= read -r line; do
        if [ "$found" = "true" ]; then
            echo "$line" | grep -q "^\["
            if [ $? -eq 0 ]; then
                found=false
            else # still in section so keep skipping
                continue
            fi
        elif echo "$line" | grep -q "^\[$section\]"; then
            found=true
            changed=true
            continue
        fi
        echo "$line" >> $temp_file
    done < "$config_file"

    if [ "$changed" = "true" ]; then
        mv $temp_file "$config_file"
    else
        rm $temp_file
    fi
    return 0
}

PRINTER_CONFIG_DIR=/usr/data/printer_data/config/
config_file=$PRINTER_CONFIG_DIR/printer.cfg

if [ "$1" = "--file" ]; then
    shift
    if [ -n "$1" ] && [ -f "${PRINTER_CONFIG_DIR}/$1" ]; then
        config_file="${PRINTER_CONFIG_DIR}/$1"
    elif [ -n "$1" ] && [ -f "${HOME}/$1" ]; then # local testing
        config_file="${HOME}/$1"
    fi
    shift
fi

if [ ! -f "$config_file" ]; then
    echo "Invalid config file: $config_file"
    exit 1
fi

action=$1
if [ "$action" = "--remove-section" ]; then
    section=$2
    if [ -z "$section" ]; then
        echo "ERROR: No section specified"
        exit 1
    fi
    remove_section "$config_file" "$section"
    exit $?
elif [ "$action" = "--remove-section-entry" ]; then
    section=$2
    if [ -z "$section" ]; then
        echo "ERROR: No section specified"
        exit 1
    fi
    entry=$3
    if [ -z "$entry" ]; then
        echo "ERROR: No $section entry specified"
        exit 1
    fi
    remove_section_entry "$config_file" "$section" "$entry"
    exit $?
elif [ "$action" = "--replace-section-entry" ]; then
    section=$2
    if [ -z "$section" ]; then
        echo "ERROR: No section specified"
        exit 1
    fi
    entry=$3
    if [ -z "$entry" ]; then
        echo "ERROR: No $section entry specified"
        exit 1
    fi
    value=$4
    if [ -z "$value" ]; then
        echo "ERROR: No $section entry $entry value specified"
        exit 1
    fi
    replace_section_entry "$config_file" "$section" "$entry" "$value"
    exit $?
elif [ "$action" = "--add-include" ]; then
    include="$2"
    if [ -z "$include" ]; then
        echo "ERROR: No section specified"
        exit 1
    fi
    add_include "$config_file" "$include"
    exit $?
elif [ "$action" = "--remove-include" ]; then
    include="$2"
    if [ -z "$include" ]; then
        echo "ERROR: No section specified"
        exit 1
    fi
    remove_include "$config_file" "$include"
    exit $?
else
    echo "Invalid action: $1"
    echo "$(basename $0): [--file cfgfile] --add-include <include>"
    echo "$(basename $0): [--file cfgfile] --remove-include <include>"
    echo "$(basename $0): [--file cfgfile] --remove-section <section>"
    echo "$(basename $0): [--file cfgfile] --replace-section-entry <section> <entry key> <entry value>"
    echo "$(basename $0): [--file cfgfile] --remove-section-entry <section> <entry key>"
    exit 1
fi
