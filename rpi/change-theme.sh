#!/bin/sh

BASEDIR=$HOME

if [ "$1" != "simpleaf" ] && [ "$1" != "stock" ]; then
  echo "Invalid choice - must specify either simpleaf or stock!"
  exit 1
fi

if [ "$1" = "simpleaf" ]; then
  echo "Applying Simple AF Fluidd theme ..."
  mkdir -p $BASEDIR/printer_data/config/.fluidd-theme || exit $?
  cp $BASEDIR/pellcorp/config/fluidd-theme/custom.css $BASEDIR/printer_data/config/.fluidd-theme/ || exit $?
  cp $BASEDIR/pellcorp/config/fluidd-theme/background.gif $BASEDIR/printer_data/config/.fluidd-theme/ || exit $?
  cp $BASEDIR/pellcorp/config/fluidd-theme/logo_SimpleAF.svg $BASEDIR/printer_data/config/.fluidd-theme/ || exit $?
  curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
    -d '{"namespace":"fluidd","key":"uiSettings.theme","value":{"isDark":true,"logo":{"src":"logo_SimpleAF.svg"},"color":"#5a7df2","backgroundLogo":true}}' > /dev/null

  echo "Applying Simple AF Mainsail theme ..."
  mkdir -p $BASEDIR/printer_data/config/.theme || exit $?
  cp $BASEDIR/pellcorp/config/mainsail-theme/custom.css $BASEDIR/printer_data/config/.theme/ || exit $?
  cp $BASEDIR/pellcorp/config/mainsail-theme/background.gif $BASEDIR/printer_data/config/.theme/ || exit $?
  cp $BASEDIR/pellcorp/config/mainsail-theme/sidebar-logo.svg $BASEDIR/printer_data/config/.theme/ || exit $?
  curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
    -d '{"namespace":"mainsail","key":"uiSettings.mode","value":"dark"}' > /dev/null
  curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
    -d '{"namespace":"mainsail","key":"uiSettings.primary","value":"#5a7df2"}' > /dev/null
else # stock
  echo "Removing Simple AF Fluidd theme ..."
  rm -rf $BASEDIR/printer_data/config/.fluidd-theme
  curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=fluidd&key=uiSettings.theme" > /dev/null

  echo "Removing Simple AF Mainsail theme ..."
  rm -rf $BASEDIR/printer_data/config/.theme
  curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.mode" > /dev/null
  curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.primary" > /dev/null
fi
