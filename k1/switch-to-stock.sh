#!/bin/sh

mode=stock
if [ "$1" = "--revert" ]; then
    mode=revert
fi

CONFIG_HELPER="/usr/data/pellcorp/k1/config-helper.py"

# its really important that the creality-backup.tar.gz exists because with
# switch-to-stock.sh, it does not restore the screen so doing the initial
# calibration is not enforced
if [ -f /usr/data/backups/creality-backup.tar.gz ]; then
    if [ "$mode" = "stock" ]; then
        if [ -L /usr/share/klipper ]; then
            echo "Switching to Stock ..."

            if [ -f /etc/init.d/S55klipper_service ]; then
                /etc/init.d/S55klipper_service stop
            fi

            # we want a backup of the latest simple af config so we can quickly switch back
            TIMESTAMP=latest /usr/data/pellcorp/k1/tools/backups.sh --create

            rm /usr/share/klipper
            rm -rf /overlay/upper/usr/share/klipper
            rm /overlay/upper/etc/init.d/S57klipper_mcu
            rm /overlay/upper/etc/init.d/S55klipper_service
            mount -o remount /

            # these firmware files are for pre-release boards and confuse the check-firmware.sh
            rm /usr/share/klipper/fw/K1/mcu*110*
            rm /usr/share/klipper/fw/K1/noz*110*
            rm /usr/share/klipper/fw/K1/bed*100*

            rm -rf /usr/data/printer_data/config/*.cfg
            rm -rf /usr/data/printer_data/config/*.conf

            # need these files restored back so that moonraker starts correctly
            cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/
            cp /usr/data/pellcorp/k1/webcam.conf /usr/data/printer_data/config/
            cp /usr/data/pellcorp/k1/notifier.conf /usr/data/printer_data/config/

            tar -zxf /usr/data/backups/creality-backup.tar.gz -C /usr/data

            # to support grumpyscreen macros
            cp /usr/data/pellcorp/k1/guppyscreen-stock.cfg /usr/data/printer_data/config/guppyscreen.cfg
            $CONFIG_HELPER --add-include "guppyscreen.cfg" || exit $?
            # so we can have messages in the guppyscreen stock cfg file
            $CONFIG_HELPER --add-section "respond" || exit $?
            sync
        else
            echo "WARN: Stock is already active"
            exit 1
        fi
    else # revert
        if [ ! -L /usr/share/klipper ] && [ -f /usr/data/backups/backup-latest.tar.gz ]; then
            echo "Switching to SimpleAF ..."

            if [ -f /etc/init.d/S57klipper_mcu ]; then
                /etc/init.d/S57klipper_mcu stop
            fi
            if [ -f /etc/init.d/S55klipper_service ]; then
                /etc/init.d/S55klipper_service stop
            fi
            rm -rf /usr/share/klipper
            ln -sf /usr/data/klipper /usr/share/
            rm -rf /usr/data/printer_data/config/*.cfg
            rm -rf /usr/data/printer_data/config/*.conf
            cp /usr/data/pellcorp/k1/services/S55klipper_service /etc/init.d/
            if [ -f /etc/init.d/S57klipper_mcu ]; then
                rm /etc/init.d/S57klipper_mcu
            fi
            /usr/data/pellcorp/k1/tools/backups.sh --restore backup-latest.tar.gz
        else
            echo "WARN: Stock is not active"
            exit 1
        fi
    fi

    echo
    /usr/data/pellcorp/k1/tools/check-firmware.sh
    exit 0
else
    echo "ERROR: Switching to stock is not supported for current installation"
    exit 1
fi
