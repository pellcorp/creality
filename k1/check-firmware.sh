#!/bin/sh

VERSION_FILE=/usr/data/mcu.versions
FW_DIR=/usr/data/klipper/fw/K1

if [ -f /etc/init.d/S13mcu_update ]; then
    # add a sanity check to make sure everyone is running simple af which has S13mcu_update pointing at
    # klipper/fw/K1 directory
    mcu_update_fw_root_dir=$(cat /etc/init.d/S13mcu_update | grep FW_ROOT_DIR= | awk -F '=' '{print $2}')
    if [ "${mcu_update_fw_root_dir}/K1" != "$FW_DIR" ]; then
        echo "It looks like you have not run the installer.sh in a while, the /etc/init.d/S13mcu_update file"
        echo "should be pointing at $FW_DIR for firmware files, but its actually pointing at "
        echo "${mcu_update_fw_root_dir}/K1!"
        exit 1
    fi

    # we can't check versions if the S13mcu_update is too old to be even writing this file
    mcu_update_version_file=$(cat /etc/init.d/S13mcu_update | grep VERSION_FILE= | awk -F '=' '{print $2}')
    if [ "$mcu_update_version_file" != "$VERSION_FILE" ]; then
        echo "It looks like you have not run the installer.sh in a while, the /etc/init.d/S13mcu_update file"
        echo "should be pointing at $VERSION_FILE to write the mcu.versions file, but its actually pointing at "
        echo "${mcu_update_version_file}!"
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

    if [ "x$fw_bed_version" = "x" ] || [ "$fw_bed_version" != "$file_bed_version" ]; then
        firmware_upgrade_required=true
    fi

    if [ "x$fw_noz_version" = "x" ] || [ "$fw_noz_version" != "$file_noz_version" ]; then
        firmware_upgrade_required=true
    fi
fi

if [ "$firmware_upgrade_required" = "true" ]; then
    echo "You MUST power cycle your printer to upgrade MCU firmware!"
fi
