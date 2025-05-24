#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh
mode=$1

grep -q "nginx" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  default_ui=fluidd
  if [ -f /etc/nginx/sites-enabled/mainsail ]; then
    grep "#listen" /etc/nginx/sites-enabled/mainsail > /dev/null
    if [ $? -ne 0 ]; then
      default_ui=mainsail
    fi
  fi

  command -v /usr/sbin/nginx > /dev/null
  if [ $? -ne 0 ]; then
    echo
    echo "INFO: Installing nginx ..."

    retry sudo apt-get install -y nginx || exit $?
  fi

  # from a security point of view letting nginx be run as a user with sudo is generally considered
  # bad form, so I will settle for giving nginx access to the users local directory to access
  # fluidd and mainsail
  sudo chmod o+rx $BASEDIR

  sudo cp $BASEDIR/pellcorp/rpi/nginx/upstreams.conf /etc/nginx/conf.d/ || exit $?
  sudo cp $BASEDIR/pellcorp/rpi/nginx/fluidd /etc/nginx/sites-enabled/ || exit $?
  sudo sed -i "s:\$HOME:$BASEDIR:g" /etc/nginx/sites-enabled/fluidd
  sudo cp $BASEDIR/pellcorp/rpi/nginx/mainsail /etc/nginx/sites-enabled/ || exit $?
  sudo sed -i "s:\$HOME:$BASEDIR:g" /etc/nginx/sites-enabled/mainsail
  sudo cp $BASEDIR/pellcorp/rpi/nginx/common_vars.conf /etc/nginx/conf.d/ || exit $?
  [ -f /etc/nginx/sites-enabled/default ] && sudo rm /etc/nginx/sites-enabled/default

  if [ "$default_ui" = "mainsail" ]; then
    echo "INFO: Restoring mainsail as default UI"
    sudo sed -i 's/.*listen 80 default_server;/    #listen 80 default_server;/g' /etc/nginx/sites-enabled/fluidd || exit $?
    sudo sed -i 's/.*#listen 80 default_server;/    listen 80 default_server;/g' /etc/nginx/sites-enabled/mainsail || exit $?
  fi

  sudo systemctl restart nginx

  echo "nginx" >> $BASEDIR/pellcorp.done
fi
