#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh
mode=$1

grep -q "fluidd" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  if [ "$mode" != "update" ] && [ -d $BASEDIR/fluidd ]; then
    rm -rf $BASEDIR/fluidd
  fi

  if [ ! -d $BASEDIR/fluidd ]; then
    echo
    echo "INFO: Installing fluidd ..."

    command -v curl > /dev/null
    if [ $? -ne 0 ]; then
      retry sudo apt-get install -y curl; error
    fi
    command -v unzip > /dev/null
    if [ $? -ne 0 ]; then
      retry sudo apt-get install -y unzip; error
    fi

    mkdir -p $BASEDIR/fluidd
    curl -L "https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip" -o $BASEDIR/fluidd.zip || exit $?
    unzip -qd $BASEDIR/fluidd $BASEDIR/fluidd.zip || exit $?
    rm $BASEDIR/fluidd.zip

    if [ ! -d $BASEDIR/printer_data/config/.fluidd-theme ]; then
      mkdir -p $BASEDIR/printer_data/config/.fluidd-theme || exit $?
      cp $BASEDIR/pellcorp/config/theme/logo_simpleaf.svg $BASEDIR/printer_data/config/.fluidd-theme/logo.svg || exit $?
      # fluidd docs are wrong you can't drop a logo.svg into the fluidd theme directory, I opened a bug maybe they
      # actually change the code so it can actually work and I can remove this shit
      curl -s -X POST "http://localhost:7125/server/database/item" \
          -H "Content-Type: application/json" \
          -d '{"namespace":"fluidd","key":"uiSettings.theme.logo.src","value":"server/files/config/.fluidd-theme/logo.svg"}' > /dev/null
    fi
  fi

  echo "fluidd" >> $BASEDIR/pellcorp.done
fi
