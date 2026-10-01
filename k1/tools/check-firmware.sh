#!/bin/sh

if [ -f /usr/bin/get_sn_mac.sh ]; then
  MODEL=$(/usr/bin/get_sn_mac.sh model)
  if [ "$MODEL" = "Nebula Pad" ]; then
    MODEL=NEBULA
  fi
else
  echo "FATAL: This script is not supported on non Creality OS!"
  exit 0
fi

# Nebula doesnt have firmware we can update
if [ "$MODEL" = "NEBULA" ]; then
    echo "INFO: Your MCU Firmware is up to date!"
    exit 0
fi

VERSION_FILE=/usr/data/mcu.versions
FW_DIR=/usr/share/klipper/fw/K1
if [ "$MODEL" = "F003" ] || [ "$MODEL" = "F005" ] || [ "$MODEL" = "F004" ]; then
  FW_DIR=/usr/share/klipper/fw/$MODEL
elif [ "$MODEL" = "F001" ] || [ "$MODEL" = "F002" ]; then
  FW_DIR=/usr/share/klipper/fw/F001
fi

if [ -f /etc/init.d/S13mcu_update ]; then
    mcu_update_version_file=$(cat /etc/init.d/S13mcu_update | grep VERSION_FILE= | awk -F '=' '{print $2}')
    if [ "$mcu_update_version_file" != "$VERSION_FILE" ]; then
        echo "ERROR: It looks like you have not run the installer.sh in a while, the /etc/init.d/S13mcu_update file is outdated"
        exit 1
    fi
else
    echo "ERROR: Missing /etc/init.d/S13mcu_update - something bad has happened"
    exit 1
fi

firmware_upgrade_required=true
# a missing version file either means its an older installation or there was a failure to properly
# start one or more of the MCUs so a power cycle is recommended anyway
if [ -f $VERSION_FILE ] && [ -d $FW_DIR ]; then
    firmware_upgrade_required=false

    fw_mcu_version=$(cat $VERSION_FILE | grep "mcu_version" | awk -F '=' ' {print $2}')

    # check for the exact file it reports being current rather than assuming which family to compare against
    if [ "x$fw_mcu_version" = "x" ] || [ ! -f "$FW_DIR/${fw_mcu_version}.bin" ]; then
        firmware_upgrade_required=true
    fi

    # The Ender 3 V3 KE does not have a nozzle mcu!
    if [ "$MODEL" != "F005" ]; then
      fw_noz_version=$(cat $VERSION_FILE | grep "noz_version" | awk -F '=' ' {print $2}')

      if [ "x$fw_noz_version" = "x" ] || [ ! -f "$FW_DIR/${fw_noz_version}.bin" ]; then
          firmware_upgrade_required=true
      fi

      # So the CR10SE (F003) has no bed mcu far as I can tell
      if [ "$MODEL" != "F003" ]; then
        fw_bed_version=$(cat $VERSION_FILE | grep "bed_version" | awk -F '=' ' {print $2}')

        # ignore missing firmware for the bed which will occur if someone has removed their bed mcu
        if [ "x$fw_bed_version" != "x" ] && [ ! -f "$FW_DIR/${fw_bed_version}.bin" ]; then
            firmware_upgrade_required=true
        fi
      fi
    fi
fi

if [ "$firmware_upgrade_required" = "true" ]; then
    echo "WARNING: MCU Firmware updates are pending you need to power cycle your printer!"
    if [ "$1" = "--status" ]; then
        exit 1
    fi
else
    echo "INFO: Your MCU Firmware is up to date!"
    if [ "$1" = "--status" ]; then
        exit 0
    fi
fi
