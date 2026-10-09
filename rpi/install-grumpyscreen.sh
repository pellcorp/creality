#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"

mode=$1

grep -q "grumpyscreen" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  echo
  echo "INFO: Installing grumpyscreen ..."

  if [ "$(sudo systemctl is-enabled KlipperScreen 2> /dev/null)" = "enabled" ]; then
    echo "INFO: Stop and disable KlipperScreen"
    sudo systemctl stop KlipperScreen > /dev/null 2>&1
    sudo systemctl disable KlipperScreen > /dev/null 2>&1
  fi

  if [ -f /etc/systemd/system/grumpyscreen.service ]; then
    sudo systemctl stop grumpyscreen > /dev/null 2>&1
  fi

  [ -d  $BASEDIR/guppyscreen ] && rm -rf $BASEDIR/guppyscreen

  # older installs came from the tar release which has no release_info.json for moonraker
  if [ -d $BASEDIR/grumpyscreen ] && [ ! -f $BASEDIR/grumpyscreen/release_info.json ]; then
    echo
    echo "INFO: Forcing update of grumpyscreen"
    rm -rf $BASEDIR/grumpyscreen
  fi

  command -v curl > /dev/null
  if [ $? -ne 0 ]; then
    retry sudo apt-get install -y curl || exit $?
  fi

  command -v unzip > /dev/null
  if [ $? -ne 0 ]; then
    retry sudo apt-get install -y unzip || exit $?
  fi

  if [ ! -d $BASEDIR/grumpyscreen ]; then
    # the versioned zip releases include the release_info.json moonraker needs to update grumpyscreen
    retry curl -L "https://github.com/pellcorp/grumpyscreen/releases/latest/download/grumpyscreen-rpi.zip" -o $BASEDIR/grumpyscreen.zip || exit $?
    mkdir -p $BASEDIR/grumpyscreen
    unzip -qd $BASEDIR/grumpyscreen $BASEDIR/grumpyscreen.zip || exit $?
    rm $BASEDIR/grumpyscreen.zip
    chmod +x $BASEDIR/grumpyscreen/grumpyscreen
  fi

  # only grumpyscreen installs get the moonraker update manager section
  cp $BASEDIR/pellcorp/rpi/grumpyscreen.conf $BASEDIR/printer_data/config/ || exit $?
  $CONFIG_HELPER --file moonraker.conf --add-include "grumpyscreen.conf" || exit $?

  cp $BASEDIR/pellcorp/config/grumpyscreen.ini $BASEDIR/printer_data/config/
  [ -f $BASEDIR/printer_data/config/grumpyscreen.cfg ] && rm $BASEDIR/printer_data/config/grumpyscreen.cfg

  # si that you can print
  if [ ! -L $BASEDIR/printer_data/gcodes/usb ]; then
    ln -sf /media/usb $BASEDIR/printer_data/gcodes/usb
  fi

  sudo cp $BASEDIR/pellcorp/rpi/services/grumpyscreen.service /etc/systemd/system/ || exit $?
  sudo sed -i "s:\$HOME:$BASEDIR:g" /etc/systemd/system/grumpyscreen.service
  sudo sed -i "s:User=pi:User=$USER:g" /etc/systemd/system/grumpyscreen.service

  kinematics=$($CONFIG_HELPER --get-section-entry "printer" "kinematics")
  if [ "$kinematics" = "cartesian" ]; then
    sudo sed -i "s:INVERT_Z_ICON=false:INVERT_Z_ICON=true:g" /etc/systemd/system/grumpyscreen.service
  fi

  sudo systemctl daemon-reload
  sudo systemctl enable grumpyscreen

  echo "grumpyscreen" >> $BASEDIR/pellcorp.done
fi
