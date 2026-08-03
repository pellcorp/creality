#!/bin/sh

# now we force wifi to restart if these scripts exist
if [ -f /usr/bin/wifi_down.sh ] && [ -f /usr/bin/wifi_up.sh ]; then
  /usr/bin/wifi_down.sh
  /usr/bin/wifi_up.sh
fi
