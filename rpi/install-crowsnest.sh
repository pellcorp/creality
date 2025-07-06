#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
mode=$1

grep -q "crowsnest" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  if [ "$mode" != "update" ] || [ ! -f /usr/local/bin/crowsnest ]; then
    echo
    echo "INFO: Installing crowsnest ..."

    [ -d $BASEDIR/crowsnest ] && rm -rf $BASEDIR/crowsnest
    git clone https://github.com/mainsail-crew/crowsnest.git $BASEDIR/crowsnest || exit $?
    cd $BASEDIR/crowsnest

    command -v make > /dev/null
    if [ $? -ne 0 ]; then
      retry sudo DEBIAN_FRONTEND=noninteractive apt-get --yes install make; error
    fi

    sudo CROWSNEST_UNATTENDED=1 CROWSNEST_ADD_CROWSNEST_MOONRAKER=0 make install > /tmp/crowsnest.log
    if [ $? -ne 0 ]; then
      echo "ERROR: Crowsnest installation failed - see /tmp/crowsnest.log for error"
      exit 1
    fi

    # we replace the one copied in there with ours so that config overrides work
    cp $BASEDIR/pellcorp/rpi/crowsnest.conf $BASEDIR/printer_data/config/ || exit $?
  fi

  $CONFIG_HELPER --file moonraker.conf --overrides $BASEDIR/pellcorp/rpi/crowsnest-um.conf --quiet || exit $?
  cp $BASEDIR/pellcorp/rpi/webcam.conf $BASEDIR/printer_data/config/ || exit $?
  $CONFIG_HELPER --file moonraker.conf --add-include "webcam.conf" || exit $?
  sudo systemctl restart crowsnest
  echo "crowsnest" >> $BASEDIR/pellcorp.done
fi
