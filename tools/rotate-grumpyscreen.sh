#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi

if [ $1 -gt 0 ] && [ $1 -lt 4 ]; then
  cp $BASEDIR/guppyscreen/guppyscreen.json $BASEDIR/guppyscreen/guppyscreen.json.backup
  jq ".display_rotate = $1" $BASEDIR/guppyscreen/guppyscreen.json > $BASEDIR/guppyscreen/guppyscreen.json.$$
  if [ $? -eq 0 ]; then
    mv $BASEDIR/guppyscreen/guppyscreen.json.$$ $BASEDIR/guppyscreen/guppyscreen.json
    sudo systemctl restart grumpyscreen
    exit 0
  else
    echo "ERROR: Failed to update display rotate setting"
    exit 1
  fi
else
  echo "ERROR: Invalid rotation value, must be between 1 an 3"
  exit 1
fi
