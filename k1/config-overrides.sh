#!/bin/sh

CONFIG_OVERRIDES="/usr/data/pellcorp/k1/config-overrides.py"

if [ ! -f /usr/data/pellcorp-backups/printer.pellcorp.cfg ]; then
    echo "ERROR: /usr/data/pellcorp-backups/printer.pellcorp.cfg missing"
    exit 1
fi

if [ -f /usr/data/pellcorp-overrides.cfg ]; then
    echo "ERROR: /usr/data/pellcorp-overrides.cfg exists!"
    exit 1
fi

override_file() {
    local file=$1

    overrides_file="/usr/data/pellcorp-overrides/$file"
    if [ -f "$overrides_file" ]; then
        echo "ERROR: Override File $overrides_file already exists!"
        exit 1
    fi

    original_file="/usr/data/pellcorp/k1/$file"
    updated_file="/usr/data/printer_data/config/$file"
    
    if [ "$file" = "printer.cfg" ] && [ -f "/usr/data/pellcorp-backups/printer.pellcorp.cfg" ]; then
        original_file="/usr/data/pellcorp-backups/printer.pellcorp.cfg"
    elif [ "$file" = "sensorless.cfg" ]|| [ "$file" = "useful_macros.cfg" ] || [ "$file" = "start_end.cfg" ] || [ ! -f "/usr/data/pellcorp/k1/$file" ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    fi

    $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" || exit $?
}

mkdir -p /usr/data/pellcorp-overrides
# remove existing override config files with -f
if [ "$1" = "-f" ]; then
    rm /usr/data/pellcorp-overrides/*
fi

# special case for moonraker.secrets
if [ -f /usr/data/printer_data/config/KAMP_Settings.cfg ] && [ -f /usr/data/pellcorp/k1/moonraker.secrets ]; then
    diff /usr/data/printer_data/moonraker.secrets /usr/data/pellcorp/k1/moonraker.secrets > /dev/null
    if [ $? -ne 0 ]; then
        if [ -f /usr/data/pellcorp-overrides/moonraker.secrets ]; then
            echo "ERROR: Override File /usr/data/pellcorp-overrides/moonraker.secrets already exists!"
            exit 1
        fi
        cp  /usr/data/printer_data/moonraker.secrets /usr/data/pellcorp-overrides/
    fi
fi

cfg_files=$(ls /usr/data/printer_data/config/*.cfg)
for file in $cfg_files; do
    file=$(basename $file)
    override_file $file
done

conf_files=$(ls /usr/data/printer_data/config/*.conf)
for file in $conf_files; do
    file=$(basename $file)
    override_file $file
done
