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

    if [ -L /usr/data/printer_data/config/$file ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    fi

    overrides_file="/usr/data/pellcorp-overrides/$file"
    original_file="/usr/data/pellcorp/k1/$file"
    updated_file="/usr/data/printer_data/config/$file"
    
    if [ "$file" = "printer.cfg" ] && [ -f "/usr/data/pellcorp-backups/printer.pellcorp.cfg" ]; then
        original_file="/usr/data/pellcorp-backups/printer.pellcorp.cfg"
    elif [ "$file" = "KAMP_Settings.cfg" ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ ! -f "/usr/data/pellcorp/k1/$file" ]; then
        echo "Backing up /usr/data/printer_data/config/$file ..."
        cp  /usr/data/printer_data/config/$file /usr/data/pellcorp-overrides/
        return 0
    fi

    if [ -f $overrides_file ]; then
      rm $overrides_file
    fi
    $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" || exit $?

    if [ "$file" = "printer.cfg" ]; then
      if [ -f /usr/data/pellcorp-overrides/printer.cfg.save_config ]; then
        rm /usr/data/pellcorp-overrides/printer.cfg.save_config
      fi
      saves=false
      while IFS= read -r line; do
          if [ "$line" = "#*# <---------------------- SAVE_CONFIG ---------------------->" ]; then
            saves=true
            echo "" > /usr/data/pellcorp-overrides/printer.cfg.save_config
            echo "Saving SAVE_CONFIG state to /usr/data/pellcorp-overrides/printer.cfg.save_config"
          fi
          if [ "$saves" = "true" ]; then
            echo "$line" >> /usr/data/pellcorp-overrides/printer.cfg.save_config
          fi
        done < "$updated_file"
    fi
}

mkdir -p /usr/data/pellcorp-overrides

# special case for moonraker.secrets
if [ -f /usr/data/printer_data/moonraker.secrets ] && [ -f /usr/data/pellcorp/k1/moonraker.secrets ]; then
    diff /usr/data/printer_data/moonraker.secrets /usr/data/pellcorp/k1/moonraker.secrets > /dev/null
    if [ $? -ne 0 ]; then
        echo "Backing up /usr/data/printer_data/moonraker.secrets..."
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
