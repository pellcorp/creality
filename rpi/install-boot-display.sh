#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh

grep -q "boot-display" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  if [ "$mode" != "update" ] && [ -d /usr/share/plymouth/themes/simpleaf ]; then
    sudo rm -rf /usr/share/plymouth/themes/simpleaf
  fi

  if [ ! -d /usr/share/plymouth/themes/simpleaf ]; then
    command -v plymouth > /dev/null
    if [ $? -eq 0 ]; then
      sudo mkdir -p /usr/share/plymouth/themes/simpleaf

      command -v unzip > /dev/null
      if [ $? -ne 0 ]; then
        retry apt-get install -y unzip; error
      fi

      sudo unzip -qd /usr/share/plymouth/themes/simpleaf $BASEDIR/pellcorp/rpi/plymouth/simpleaf.zip
      sudo cp $BASEDIR/pellcorp/rpi/plymouth/simpleaf.plymouth /usr/share/plymouth/themes/simpleaf/
      sudo cp $BASEDIR/pellcorp/rpi/plymouth/simpleaf.script /usr/share/plymouth/themes/simpleaf/
      sudo plymouth-set-default-theme -R simpleaf
#      sudo update-initramfs -u
      echo "boot-display" >> $BASEDIR/pellcorp.done
    else
      echo "INFO: Skipping theme install as plymouth is not installed"
    fi
  fi
fi
