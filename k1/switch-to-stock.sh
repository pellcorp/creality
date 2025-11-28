#!/bin/sh

if [ -f /usr/bin/get_sn_mac.sh ]; then
  MODEL=$(/usr/bin/get_sn_mac.sh model)
  if [ "$MODEL" = "Nebula Pad" ]; then
    MODEL=NEBULA
  fi
else
  echo "FATAL: This script is not supported on non Creality OS!"
  exit 1
fi

mode=stock
if [ "$1" = "--revert" ]; then
  mode=revert
elif [ "$1" = "--update" ]; then
  mode=update
fi

CONFIG_HELPER="/usr/data/pellcorp/tools/config-helper.py"

if [ -f /usr/data/backups/creality-backup.tar.gz ]; then
  if [ "$mode" = "update" ]; then
    if [ -d /usr/share/klipper ]; then
      cd /usr/data
      tar -zcf /usr/data/backups/creality-backup.tar.gz printer_data/config/*.cfg
      sync
      cd ~ > /dev/null
    else
      echo "WARN: Printer is not currently stock"
      exit 1
    fi
  elif [ "$mode" = "stock" ]; then
    if [ -L /usr/share/klipper ]; then
      echo "Switching to Stock ..."

      if [ -f /etc/init.d/S55klipper_service ]; then
          /etc/init.d/S55klipper_service stop 2> /dev/null
      fi

      # we want a backup of the latest simple af config so we can quickly switch back
      TIMESTAMP=latest /usr/data/pellcorp/tools/backups.sh --create

      rm /usr/share/klipper
      rm -rf /overlay/upper/usr/share/klipper
      rm /usr/bin/klipper_mcu
      rm /overlay/upper/usr/bin/klipper_mcu
      # for KE we don't remove klipper_mcu
      if [ -e /overlay/upper/etc/init.d/S57klipper_mcu ]; then
        rm /overlay/upper/etc/init.d/S57klipper_mcu
      fi
      rm /overlay/upper/etc/init.d/S55klipper_service
      rm /overlay/upper/etc/init.d/S99start_app
      mount -o remount /

      # remove a few services that will cause issues
      [ -f /usr/bin/upgrade-server ] && rm /usr/bin/upgrade-server
      [ -f /usr/bin/web-server ] && rm /usr/bin/web-server
      [ -f /usr/bin/Monitor ] && rm /usr/bin/Monitor

      # these firmware files are for pre-release boards and confuse the check-firmware.sh
      rm /usr/share/klipper/fw/K1/mcu*110*
      rm /usr/share/klipper/fw/K1/noz*110*
      rm /usr/share/klipper/fw/K1/bed*100*

      rm -rf /usr/data/printer_data/config/*.cfg
      rm -rf /usr/data/printer_data/config/*.conf

      # for stock screen grumpyscreen needs to be disabled
      rm /etc/init.d/S99guppyscreen

      # need these files restored back so that moonraker starts correctly
      cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/
      cp /usr/data/pellcorp/k1/webcam.conf /usr/data/printer_data/config/
      cp /usr/data/pellcorp/config/notifier.conf /usr/data/printer_data/config/

      tar -zxf /usr/data/backups/creality-backup.tar.gz -C /usr/data
      sync
    else
      echo "WARN: Stock is already active"
      exit 1
    fi
  else # revert
    if [ ! -L /usr/share/klipper ] && [ -f /usr/data/backups/backup-latest.tar.gz ]; then
      if [ -d /usr/data/helper-script ]; then
        echo "You cannot switch back to SimpleAF as helper-script is not compatible"
        exit 1
      fi

      echo "Switching to SimpleAF ..."

      if [ -f /etc/init.d/S57klipper_mcu ]; then
          /etc/init.d/S57klipper_mcu stop 2> /dev/null
          # Ender 3 V3 KE uses rpi mcu for adxl so we need to leave it alone
          if [ "$MODEL" != "F005" ] && [ "$MODEL" != "NEBULA" ]; then
            rm /etc/init.d/S57klipper_mcu
          fi
      fi

      if [ -f /etc/init.d/S55klipper_service ]; then
          /etc/init.d/S55klipper_service stop 2> /dev/null
      fi
      if [ -f /etc/init.d/S99start_app ]; then
          /etc/init.d/S99start_app stop 2> /dev/null
          rm /etc/init.d/S99start_app
      fi

      rm -rf /usr/share/klipper
      ln -sf /usr/data/klipper /usr/share/
      rm -rf /usr/data/printer_data/config/*.cfg
      rm -rf /usr/data/printer_data/config/*.conf
      cp /usr/data/pellcorp/k1/services/S55klipper_service /etc/init.d/
      cp /usr/data/pellcorp/k1/services/S99guppyscreen /etc/init.d/
      ln -sf /usr/data/klipper/fw/K1/klipper_host_mcu /usr/bin/klipper_mcu
      /usr/data/pellcorp/tools/backups.sh --restore backup-latest.tar.gz
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
