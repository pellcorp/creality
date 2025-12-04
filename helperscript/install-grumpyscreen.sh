#!/bin/sh

# everything else in the script assumes its cloned to /usr/data/pellcorp
# so we must verify this or shit goes wrong
if [ "$(dirname $(readlink -f $0))" != "/usr/data/pellcorp/helperscript" ]; then
  >&2 echo "FATAL: This git repo must be cloned to /usr/data/pellcorp"
  exit 1
fi

if [ ! -d /usr/data/helper-script/ ]; then
  echo "ERROR: Missing existing helper-script"
  exit 1
fi

# this is for installing over the top of guppyscreen installed onto a helper script printer
if [ ! -d /usr/data/guppyscreen ] || [ ! -f /etc/init.d/S99guppyscreen ]; then
  echo "ERROR: Missing existing guppyscreen"
  exit 1
fi

MODEL=$(/usr/bin/get_sn_mac.sh model)
if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ] || [ "$MODEL" = "K1 SE" ]; then
  model=k1
elif [ "$MODEL" = "CR-K1 Max" ]; then
  model=k1m
else
  echo "FATAL: This script is not supported for $MODEL!"
  exit 1
fi

/etc/init.d/S99guppyscreen stop > /dev/null 2>&1
killall -q guppyscreen > /dev/null 2>&1
rm /usr/data/guppyscreen/* 2> /dev/null

echo
echo "INFO: Installing grumpyscreen ..."

# remove the update macro
rm -rf /usr/data/printer_data/config/GuppyScreen/guppy_update.cfg

sed -i 's/\[calibrate_shaper_config\]//g' /usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg
sed -i 's/\[guppy_module_loader\]//g' /usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg

[ -f /usr/data/printer_data/config/guppyscreen.cfg ] && rm /usr/data/printer_data/config/guppyscreen.cfg

# remove the extras which are no longer used
[ -f /usr/share/klipper/klippy/extras/guppy_config_helper.py ] && rm /usr/share/klipper/klippy/extras/guppy_config_helper.py
[ -f /usr/share/klipper/klippy/extras/guppy_module_loader.py ] && rm /usr/share/klipper/klippy/extras/guppy_module_loader.py
[ -f /usr/share/klipper/klippy/extras/tmcstatus.py ] && rm /usr/share/klipper/klippy/extras/tmcstatus.py

# there are a few macros required by GrumpyScreen
cp /usr/data/pellcorp/helperscript/grumpy-macros.cfg /usr/data/printer_data/config/GuppyScreen/

/usr/data/pellcorp/helperscript/update-grumpyscreen.sh
