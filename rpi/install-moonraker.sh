#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh
mode=$1

grep -q "moonraker" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  if [ "$mode" != "update" ] && [ -d $BASEDIR/moonraker ]; then
      if [ -f /etc/systemd/system/moonraker.service ]; then
        sudo systemctl stop moonraker
      fi
      if [ -d $BASEDIR/printer_data/database/ ]; then
        [ -f $BASEDIR/moonraker-database.tar.gz ] && rm $BASEDIR/moonraker-database.tar.gz

        echo "INFO: Backing up moonraker database ..."
        cd $BASEDIR/printer_data/

        tar -zcf $BASEDIR/moonraker-database.tar.gz database/
        cd
      fi
      rm -rf $BASEDIR/moonraker
  fi

  if [ "$mode" != "update" ] && [ -d $BASEDIR/moonraker-env ]; then
    rm -rf $BASEDIR/moonraker-env
  fi

  # an existing bug where the moonraker secrets was not correctly copied
  if [ ! -f $BASEDIR/printer_data/moonraker.secrets ]; then
    cp $BASEDIR/pellcorp/config/moonraker.secrets $BASEDIR/printer_data/
  fi

  cp $BASEDIR/pellcorp/rpi/moonraker.conf $BASEDIR/printer_data/config/ || exit $?
  ln -sf $BASEDIR/pellcorp/rpi/moonraker.asvc $BASEDIR/printer_data/ || exit $?

  if [ ! -d $BASEDIR/moonraker/.git ]; then
    echo "INFO: Installing moonraker ..."

    [ -d $BASEDIR/moonraker ] && rm -rf $BASEDIR/moonraker
    [ -d $BASEDIR/moonraker-env ] && rm -rf $BASEDIR/moonraker-env

    git clone https://github.com/pellcorp/moonraker.git $BASEDIR/moonraker || exit $?

    if [ -f $BASEDIR/moonraker-database.tar.gz ]; then
      echo
      echo "INFO: Restoring moonraker database ..."
      cd $BASEDIR/printer_data/
      tar -zxf $BASEDIR/moonraker-database.tar.gz
      rm $BASEDIR/moonraker-database.tar.gz
      cd
    fi

    if [ -f "/boot/dietpi/.version" ]; then
      retry sudo apt-get install -y dbus; error
    fi

    $BASEDIR/moonraker/scripts/install-moonraker.sh -s
  fi

  if [ ! -f $BASEDIR/moonraker-timelapse/component/timelapse.py ]; then
    if [ -d $BASEDIR/moonraker-timelapse ]; then
      rm -rf $BASEDIR/moonraker-timelapse
    fi
    git clone https://github.com/mainsail-crew/moonraker-timelapse.git $BASEDIR/moonraker-timelapse/ || exit $?
  fi

  ln -sf $BASEDIR/moonraker-timelapse/component/timelapse.py $BASEDIR/moonraker/moonraker/components/ || exit $?
  if ! grep -q "moonraker/components/timelapse.py" "$BASEDIR/moonraker/.git/info/exclude"; then
    echo "moonraker/components/timelapse.py" >> "$BASEDIR/moonraker/.git/info/exclude"
  fi
  ln -sf $BASEDIR/moonraker-timelapse/klipper_macro/timelapse.cfg $BASEDIR/printer_data/config/ || exit $?
  cp $BASEDIR/pellcorp/rpi/timelapse.conf $BASEDIR/printer_data/config/ || exit $?

  ln -sf $BASEDIR/pellcorp/config/spoolman.cfg $BASEDIR/printer_data/config/ || exit $?
  cp $BASEDIR/pellcorp/config/spoolman.conf $BASEDIR/printer_data/config/ || exit $?

  # after an initial install do not overwrite notifier.conf or moonraker.secrets
  if [ ! -f $BASEDIR/printer_data/config/notifier.conf ]; then
    cp $BASEDIR/pellcorp/config/notifier.conf $BASEDIR/printer_data/config/ || exit $?
  fi
  if [ ! -f $BASEDIR/printer_data/moonraker.secrets ]; then
    cp $BASEDIR/pellcorp/config/moonraker.secrets $BASEDIR/printer_data/ || exit $?
  fi

  echo "moonraker" >> $BASEDIR/pellcorp.done

  sudo systemctl restart moonraker
fi
