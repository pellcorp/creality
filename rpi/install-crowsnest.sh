#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
mode=$1

# The installer should export this variable
if [ -z "$TIMESTAMP" ]; then
  export TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
fi

grep -q "crowsnest" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  if [ "$mode" != "update" ]; then
    echo
    echo "INFO: Installing crowsnest ..."

    [ -d $BASEDIR/crowsnest ] && rm -rf $BASEDIR/crowsnest
    git clone https://github.com/mainsail-crew/crowsnest.git $BASEDIR/crowsnest || exit $?
    cd $BASEDIR/crowsnest

    command -v make > /dev/null
    if [ $? -ne 0 ]; then
      retry sudo DEBIAN_FRONTEND=noninteractive apt-get --yes install make; error
    fi

    echo
    echo "INFO: Installing crowsnest ... "

    # thanks Chad for putting me onto script which seems to have resolved the alignment issues
    script -qefc "sudo CROWSNEST_UNATTENDED=1 CROWSNEST_ADD_CROWSNEST_MOONRAKER=1 make install" /dev/null
    if [ $? -eq 0 ]; then
      echo "INFO: Crownest Installation complete!"
    else
      exit 1
    fi

    # we replace the one copied in there with ours so that config overrides work
    cp $BASEDIR/pellcorp/rpi/crowsnest.conf $BASEDIR/printer_data/config/ || exit $?
  fi

  cp $BASEDIR/pellcorp/rpi/webcam.conf $BASEDIR/printer_data/config/ || exit $?
  $CONFIG_HELPER --file moonraker.conf --add-include "webcam.conf" || exit $?
  sudo systemctl restart crowsnest
  echo "crowsnest" >> $BASEDIR/pellcorp.done
fi


grep -qx "crowsnest-v5" $BASEDIR/pellcorp.done
if [ $? -ne 0 ] && [ -d $BASEDIR/crowsnest ]; then
  crowsnest_major=$(git -C $BASEDIR/crowsnest describe --tags 2> /dev/null | sed -n 's/^v\([0-9]*\)\..*/\1/p')
  if [ "$crowsnest_major" = "4" ]; then
    if [ -n "$CROWSNEST_SKIP_UPGRADE" ]; then
      echo "INFO: Crowsnest v4 detected, skipping the upgrade to v5 as CROWSNEST_SKIP_UPGRADE is set"
    elif ! curl -s -o /dev/null --max-time 10 https://github.com || ! curl -s -o /dev/null --max-time 10 https://apt.mainsail.xyz; then
      echo "WARNING: Crowsnest v4 detected, but github.com or apt.mainsail.xyz is unreachable so the upgrade to v5 was skipped, it will be retried on the next update"
    else
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
        echo "crowsnest-v5" >> $BASEDIR/pellcorp.done
      else
        echo "WARNING: Crowsnest upgrade failed, your configs are backed up in $BASEDIR/pellcorp-backups, try again manually with: cd ~/crowsnest && git pull && make upgrade"
      fi
      cd $BASEDIR
    fi
  elif [ -n "$crowsnest_major" ] && [ "$crowsnest_major" -ge 5 ]; then
    echo "crowsnest-v5" >> $BASEDIR/pellcorp.done
  fi
fi
