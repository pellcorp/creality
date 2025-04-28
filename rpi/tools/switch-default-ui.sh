#!/bin/sh

BASEDIR=$HOME

if [ "$1" != "mainsail" ] && [ "$1" != "fluidd" ]; then
  echo "Invalid choice - must specify either mainsail or fluidd!"
  exit 1
fi

sudo cp $BASEDIR/pellcorp/rpi/nginx/fluidd /etc/nginx/sites-enabled/ || exit $?
sudo cp $BASEDIR/pellcorp/rpi/nginx/mainsail /etc/nginx/sites-enabled/ || exit $?

if [ "$1" = "mainsail" ]; then
  sudo sed -i 's/.*listen 80 default_server;/    #listen 80 default_server;/g' /etc/nginx/sites-enabled/fluidd || exit $?
  sudo sed -i 's/.*#listen 80 default_server;/    listen 80 default_server;/g' /etc/nginx/sites-enabled/mainsail || exit $?
else # else fluidd
  sudo sed -i 's/.*listen 80 default_server;/    #listen 80 default_server;/g' /etc/nginx/sites-enabled/mainsail || exit $?
  sudo sed -i 's/.*#listen 80 default_server;/    listen 80 default_server;/g' /etc/nginx/sites-enabled/fluidd || exit $?
fi

echo "Restarting nginx ..."
sudo systemctl restart nginx
