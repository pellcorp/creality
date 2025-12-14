#!/bin/bash

# this allows us to make changes to Simple AF and grumpyscreen in parallel
GRUMPYSCREEN_TIMESTAMP=1765591800

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

mode=$1

grep -q "grumpyscreen" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  echo

  if [ "$mode" != "update" ] && [ -d $BASEDIR/guppyscreen ]; then
    if [ -f /etc/systemd/system/grumpyscreen.service ]; then
      sudo systemctl stop grumpyscreen > /dev/null 2>&1
    fi
    rm -rf $BASEDIR/guppyscreen
  fi

  if [ -d $BASEDIR/guppyscreen ]; then
    TIMESTAMP=$(cat $BASEDIR/guppyscreen/release.info | grep TIMESTAMP | awk -F '=' '{print $2}')
    if [ $TIMESTAMP -lt $GRUMPYSCREEN_TIMESTAMP ]; then
      echo
      echo "INFO: Forcing update of grumpyscreen"
      rm -rf $BASEDIR/guppyscreen
    fi
  fi

  if [ ! -d $BASEDIR/guppyscreen ]; then
    echo "INFO: Installing grumpyscreen ..."

    command -v curl > /dev/null
    if [ $? -ne 0 ]; then
      retry sudo apt-get install -y curl; retry
    fi

    curl -L "https://github.com/pellcorp/grumpyscreen/releases/download/main/guppyscreen-rpi.tar.gz" -o $BASEDIR/guppyscreen.tar.gz || exit $?
    tar xf $BASEDIR/guppyscreen.tar.gz -C $BASEDIR/ || exit $?
    rm $BASEDIR/guppyscreen.tar.gz

    # for config-overrides copy the base cfg file
    mv $BASEDIR/guppyscreen/grumpyscreen.cfg $BASEDIR/pellcorp-backups/
  fi

  if [ -f $BASEDIR/pellcorp-backups/grumpyscreen.cfg ]; then
    cp $BASEDIR/pellcorp-backups/grumpyscreen.cfg $BASEDIR/printer_data/config/grumpyscreen.ini

    # we want grumpyscreen.cfg to be editable from fluidd / mainsail we do that with a soft link
    ln -sf $BASEDIR/printer_data/config/grumpyscreen.ini $BASEDIR/guppyscreen/grumpyscreen.cfg

    [ -f $BASEDIR/printer_data/config/grumpyscreen.cfg ] && rm $BASEDIR/printer_data/config/grumpyscreen.cfg
  fi

  cp $BASEDIR/pellcorp/rpi/services/cursor.sh $BASEDIR/guppyscreen/
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
