#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

grep -q "fluidd-theme" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  echo
  echo "INFO: Setting up Simple AF Fluidd theme ..."

  mkdir -p $BASEDIR/printer_data/config/.fluidd-theme || exit $?
  cp $BASEDIR/pellcorp/config/fluidd-theme/custom.css $BASEDIR/printer_data/config/.fluidd-theme/ || exit $?
  cp $BASEDIR/pellcorp/config/fluidd-theme/background.gif $BASEDIR/printer_data/config/.fluidd-theme/ || exit $?
  cp $BASEDIR/pellcorp/config/fluidd-theme/logo_SimpleAF.svg $BASEDIR/printer_data/config/.fluidd-theme/ || exit $?

  curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
    -d '{"namespace":"fluidd","key":"uiSettings.theme","value":{"isDark":true,"logo":{"src":"logo_SimpleAF.svg"},"color":"#5a7df2","backgroundLogo":true}}' > /dev/null

  echo "fluidd-theme" >> $BASEDIR/pellcorp.done
fi
