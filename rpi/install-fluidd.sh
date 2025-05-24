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
  fi

  echo "fluidd" >> $BASEDIR/pellcorp.done
fi
