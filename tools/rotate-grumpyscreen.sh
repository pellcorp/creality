#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi

if [ -f $BASEDIR/guppyscreen/guppyscreen.json ]; then
  if [ $1 -ge 0 ] && [ $1 -lt 4 ]; then
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
else
  echo "ERROR: Grumpyscreen is not installed"
  exit 1
fi
