#!/bin/sh

PREVIOUS_IP_ADDRESS=$(cat /usr/data/pellcorp.ipaddress 2> /dev/null)
if [ "$PREVIOUS_IP_ADDRESS" = "skip" ]; then
  exit 0
fi

if [ -f /usr/data/ipaddress.log ]; then
  rm /usr/data/ipaddress.log
fi

while true; do
  # so depending on how quickly ethernet gets an address there is a chance we pick up a wifi address first
  # but why the f would you enable wifi and ethernet on the printer, that just seems stupid
  CURRENT_IP_ADDRESS=$(ip a | grep "inet" | grep -v "host lo" | grep "eth0" | awk '{ print $2 }' | awk -F '/' '{print $1}' | tail -1)
  if [ -z "$CURRENT_IP_ADDRESS" ]; then
      echo "No Ethernet Address available, trying WIFI" > /usr/data/ipaddress.log
      CURRENT_IP_ADDRESS=$(ip a | grep "inet" | grep -v "host lo" | grep "wlan0" | awk '{ print $2 }' | awk -F '/' '{print $1}' | tail -1)
  fi

  if [ -n "$CURRENT_IP_ADDRESS" ]; then
    break
  else
    echo "Could not get an IP Address, retrying..." | tee -a /usr/data/ipaddress.log
    sleep 1s
  fi
done

echo
if [ -z "$PREVIOUS_IP_ADDRESS" ] || [ "$PREVIOUS_IP_ADDRESS" != "$CURRENT_IP_ADDRESS" ]; then
  if [ -n "$PREVIOUS_IP_ADDRESS" ]; then
      echo "Previous IP Address was $PREVIOUS_IP_ADDRESS" | tee /usr/data/ipaddress.log
  fi
  echo "Current IP Address is $CURRENT_IP_ADDRESS" | tee -a /usr/data/ipaddress.log

  echo "Updating webcam.conf IP Address to $CURRENT_IP_ADDRESS" | tee -a /usr/data/ipaddress.log
  echo "$CURRENT_IP_ADDRESS" > /usr/data/pellcorp.ipaddress
  sed -i '/_url/d' /usr/data/printer_data/config/webcam.conf
  echo "stream_url: http://$CURRENT_IP_ADDRESS:8080/?action=stream" >> /usr/data/printer_data/config/webcam.conf
  echo "snapshot_url: http://$CURRENT_IP_ADDRESS:8080/?action=snapshot" >> /usr/data/printer_data/config/webcam.conf
  sync

  if [ "$1" = "--init" ]; then
    # we have to restart moonraker to load the new ip address
    sudo systemctl restart moonraker
    exit 0
  else
    # a special error code to let installer.sh know that moonraker should be restarted
    exit 1
  fi
fi

exit 0
