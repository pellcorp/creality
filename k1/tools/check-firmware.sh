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

# Ender 5 Max, Ender 3 V3 KE and Nebula dont have firmware we can update
if [ "$MODEL" = "F004" ] || [ "$MODEL" = "F005" ] || [ "$MODEL" = "NEBULA" ]; then
    echo "INFO: Your MCU Firmware is up to date!"
    exit 0
fi

VERSION_FILE=/usr/data/mcu.versions
FW_DIR=/usr/share/klipper/fw/K1

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
    fw_bed_version=$(cat $VERSION_FILE | grep "bed_version" | awk -F '=' ' {print $2}')
    fw_noz_version=$(cat $VERSION_FILE | grep "noz_version" | awk -F '=' ' {print $2}')

    file_mcu_version=$(basename $(ls $FW_DIR/mcu*) .bin)
    file_bed_version=$(basename $(ls $FW_DIR/bed*) .bin)
    file_noz_version=$(basename $(ls $FW_DIR/noz*) .bin)

    if [ "x$fw_mcu_version" = "x" ] || [ "$fw_mcu_version" != "$file_mcu_version" ]; then
        firmware_upgrade_required=true
    fi

    #if [ "x$fw_bed_version" = "x" ] || [ "$fw_bed_version" != "$file_bed_version" ]; then
    #    firmware_upgrade_required=true
    #fi

    if [ "x$fw_noz_version" = "x" ] || [ "$fw_noz_version" != "$file_noz_version" ]; then
        firmware_upgrade_required=true
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
