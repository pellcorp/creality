#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
mode=$1

# The installer should export this variable
if [ -z "$TIMESTAMP" ]; then
  export TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
fi

grep -q "crowsnest" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  if [ "$mode" != "update" ]; then
    echo
    echo "INFO: Installing crowsnest ..."

    [ -d $BASEDIR/crowsnest ] && rm -rf $BASEDIR/crowsnest
    git clone https://github.com/mainsail-crew/crowsnest.git $BASEDIR/crowsnest || exit $?
    cd $BASEDIR/crowsnest

    command -v make > /dev/null
    if [ $? -ne 0 ]; then
      retry sudo DEBIAN_FRONTEND=noninteractive apt-get --yes install make; error
    fi

    sudo CROWSNEST_UNATTENDED=1 CROWSNEST_ADD_CROWSNEST_MOONRAKER=1 make install || exit $?

    # we replace the one copied in there with ours so that config overrides work
    cp $BASEDIR/pellcorp/rpi/crowsnest.conf $BASEDIR/printer_data/config/ || exit $?
  fi

  cp $BASEDIR/pellcorp/rpi/webcam.conf $BASEDIR/printer_data/config/ || exit $?
  $CONFIG_HELPER --file moonraker.conf --add-include "webcam.conf" || exit $?
  sudo systemctl restart crowsnest
  echo "crowsnest" >> $BASEDIR/pellcorp.done
fi
