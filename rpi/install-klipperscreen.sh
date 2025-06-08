#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
mode=$1

# https://klipperscreen.readthedocs.io/en/latest/Installation/#auto-install
grep -q "klipperscreen" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  echo

  if [ "$mode" != "update" ] && [ -d $BASEDIR/KlipperScreen ]; then
    if [ -f /etc/systemd/system/KlipperScreen.service ]; then
      sudo systemctl stop KlipperScreen > /dev/null 2>&1
    fi
    rm -rf $BASEDIR/KlipperScreen
  fi

  if [ ! -d $BASEDIR/KlipperScreen ]; then
    echo "INFO: Installing KlipperScreen ..."
    cd $BASEDIR
    git clone https://github.com/KlipperScreen/KlipperScreen.git

    # answer yes to all questions for default installation
    yes | ./KlipperScreen/scripts/KlipperScreen-install.sh
    cd - > /dev/null
  fi

  $CONFIG_HELPER --file moonraker.conf --overrides $BASEDIR/pellcorp/rpi/klipperscreen-um.conf --quiet || exit $?

  echo "klipperscreen" >> $BASEDIR/pellcorp.done
fi
