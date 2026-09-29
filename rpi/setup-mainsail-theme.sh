#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

grep -q "mainsail-theme" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  echo
  echo "INFO: Setting up Simple AF Mainsail theme ..."

  mkdir -p $BASEDIR/printer_data/config/.theme || exit $?
  cp $BASEDIR/pellcorp/config/mainsail-theme/custom.css $BASEDIR/printer_data/config/.theme/ || exit $?
  cp $BASEDIR/pellcorp/config/mainsail-theme/background.gif $BASEDIR/printer_data/config/.theme/ || exit $?
  cp $BASEDIR/pellcorp/config/mainsail-theme/sidebar-logo.svg $BASEDIR/printer_data/config/.theme/ || exit $?

  curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
    -d '{"namespace":"mainsail","key":"uiSettings.mode","value":"dark"}' > /dev/null
  curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
    -d '{"namespace":"mainsail","key":"uiSettings.primary","value":"#5a7df2"}' > /dev/null

  echo "mainsail-theme" >> $BASEDIR/pellcorp.done
fi
