#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

# for some reason grumpyscreen does not work on Debian 13
if [ $debian_release -ge 13 ]; then
  echo "ERROR: Grumpyscreen not supported on Debian 13"
  exit 1
fi

mode=$1

grep -q "grumpyscreen" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  echo

  if [ "$(sudo systemctl is-enabled KlipperScreen 2> /dev/null)" = "enabled" ]; then
    echo "INFO: Stop and disable KlipperScreen"
    sudo systemctl stop KlipperScreen > /dev/null 2>&1
    sudo systemctl disable KlipperScreen > /dev/null 2>&1
  fi

  if [ -f /etc/systemd/system/grumpyscreen.service ]; then
    sudo systemctl stop grumpyscreen > /dev/null 2>&1
  fi

  # we are going to replace grumpyscreen every time
  [ -d  $BASEDIR/grumpyscreen ] && rm -rf $BASEDIR/grumpyscreen
  [ -d  $BASEDIR/guppyscreen ] && rm -rf $BASEDIR/guppyscreen

  echo "INFO: Installing grumpyscreen ..."

  tar -zxf $BASEDIR/pellcorp/rpi/packages/grumpyscreen-rpi.tar.gz -C $BASEDIR || exit $?

  cp $BASEDIR/pellcorp/config/grumpyscreen.ini $BASEDIR/printer_data/config/
  [ -f $BASEDIR/printer_data/config/grumpyscreen.cfg ] && rm $BASEDIR/printer_data/config/grumpyscreen.cfg

  # si that you can print
  if [ ! -L $BASEDIR/printer_data/gcodes/usb ]; then
    ln -sf /media/usb $BASEDIR/printer_data/gcodes/usb
  fi

  cp $BASEDIR/pellcorp/rpi/services/cursor.sh $BASEDIR/grumpyscreen/
  sudo cp $BASEDIR/pellcorp/rpi/services/grumpyscreen.service /etc/systemd/system/ || exit $?
  sudo sed -i "s:\$HOME:$BASEDIR:g" /etc/systemd/system/grumpyscreen.service
  sudo sed -i "s:User=pi:User=$USER:g" /etc/systemd/system/grumpyscreen.service
  sed -i "s~support_zip_cmd:.*~support_zip_cmd: $BASEDIR/pellcorp/tools/support.sh~g" $BASEDIR/printer_data/config/grumpyscreen.ini
  sed -i "s~factory_reset_cmd:.*~support_zip_cmd:~g" $BASEDIR/printer_data/config/grumpyscreen.ini
  # the current grumpy release fucks this up so clean it up for rpi
  sed -i "s~factory_reset_cmd:.*~factory_reset_cmd:~g" $BASEDIR/printer_data/config/grumpyscreen.ini
  sudo systemctl daemon-reload
  sudo systemctl enable grumpyscreen

  echo "grumpyscreen" >> $BASEDIR/pellcorp.done
fi
