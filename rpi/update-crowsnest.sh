#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

# The installer should export this variable
if [ -z "$TIMESTAMP" ]; then
  export TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
fi

if [ ! -d $BASEDIR/crowsnest ]; then
  echo "ERROR: Crowsnest is not installed"
  exit 1
fi

crowsnest_major=$(git -C $BASEDIR/crowsnest describe --tags 2> /dev/null | sed -n 's/^v\([0-9]*\)\..*/\1/p')
if [ -n "$crowsnest_major" ] && [ "$crowsnest_major" -ge 5 ]; then
  echo "INFO: Crowsnest is already on v5 or later"
  exit 0
fi

if ! curl -s -o /dev/null --max-time 10 https://github.com || ! curl -s -o /dev/null --max-time 10 https://apt.mainsail.xyz; then
  echo "WARNING: github.com or apt.mainsail.xyz is unreachable, try again later"
  exit 1
fi

echo
echo "INFO: Upgrading crowsnest to v5 ..."
mkdir -p $BASEDIR/pellcorp-backups
for file in crowsnest.conf moonraker.conf; do
  [ -f $BASEDIR/printer_data/config/$file ] && cp $BASEDIR/printer_data/config/$file $BASEDIR/pellcorp-backups/$file.crowsnest-v4.$TIMESTAMP
done
cd $BASEDIR/crowsnest
git pull && script -qefc "make upgrade" /dev/null
if [ $? -eq 0 ]; then
  echo "INFO: Crowsnest upgrade complete!"
else
  echo "WARNING: Crowsnest upgrade failed, your configs are backed up in $BASEDIR/pellcorp-backups"
  exit 1
fi
cd $BASEDIR
