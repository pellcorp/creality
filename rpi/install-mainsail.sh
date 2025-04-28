#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh
mode=$1

grep -q "mainsail" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  if [ "$mode" != "update" ] && [ -d $BASEDIR/mainsail ]; then
    rm -rf $BASEDIR/mainsail
  fi

  if [ ! -d $BASEDIR/mainsail ]; then
    echo
    echo "INFO: Installing mainsail ..."

    mkdir -p $BASEDIR/mainsail || exit $?

    command -v curl > /dev/null
    if [ $? -ne 0 ]; then
      retry sudo apt-get install -y curl; error
    fi
    command -v unzip > /dev/null
    if [ $? -ne 0 ]; then
      retry apt-get install -y unzip; error
    fi
    curl -L "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o $BASEDIR/mainsail.zip || exit $?
    unzip -qd $BASEDIR/mainsail $BASEDIR/mainsail.zip || exit $?
    rm $BASEDIR/mainsail.zip
  fi

  echo "mainsail" >> $BASEDIR/pellcorp.done
  sync
fi
