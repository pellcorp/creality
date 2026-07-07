#!/bin/bash

# this allows us to make changes to Simple AF and grumpyscreen in parallel
GRUMPYSCREEN_TIMESTAMP=1783387800

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

  if [ -d $BASEDIR/grumpyscreen ]; then
    TIMESTAMP=0
    if [ -f $BASEDIR/grumpyscreen/release.info ]; then
      TIMESTAMP=$(cat $BASEDIR/grumpyscreen/release.info | grep TIMESTAMP | awk -F '=' '{print $2}')
      if [ -z "$TIMESTAMP" ]; then
        TIMESTAMP=0
      fi
    fi
    if [ $TIMESTAMP -lt $GRUMPYSCREEN_TIMESTAMP ]; then
      echo
      echo "INFO: Forcing update of grumpyscreen"
      rm -rf $BASEDIR/grumpyscreen
    fi
  fi

  command -v curl > /dev/null
  if [ $? -ne 0 ]; then
    retry sudo apt-get install -y curl || exit $?
  fi

  if [ ! -d $BASEDIR/grumpyscreen ]; then
    retry curl -L "https://github.com/pellcorp/grumpyscreen/releases/download/main/grumpyscreen-rpi.tar.gz" -o $BASEDIR/grumpyscreen.tar.gz || exit $?
    tar xf $BASEDIR/grumpyscreen.tar.gz -C $BASEDIR/ || exit $?
    rm $BASEDIR/grumpyscreen.tar.gz
  fi

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
  sed -i "s:\$HOME:$BASEDIR:g" $BASEDIR/grumpyscreen/grumpyscreen.cfg
  sudo systemctl daemon-reload
  sudo systemctl enable grumpyscreen

  echo "grumpyscreen" >> $BASEDIR/pellcorp.done
fi
