#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi

if [ -z "$1" ]; then
  probe=$(cat $BASEDIR/pellcorp.done | grep "\-probe" | awk -F '-' '{print $1}')
else
  probe=$1
fi

if [ -n "$probe" ] && [ -f "$BASEDIR/pellcorp/test/${probe}.save.config.cfg" ]; then
  $BASEDIR/pellcorp/tools/save-config-helper.py --remove-section '*'
  echo "Applying $BASEDIR/pellcorp/test/${probe}.save.config.cfg -> $BASEDIR/printer_data/config/printer.cfg ..."
  cat "$BASEDIR/pellcorp/test/${probe}.save.config.cfg" >> $BASEDIR/printer_data/config/printer.cfg
else
  echo "Invalid probe specified: $probe"
  exit 1
fi
