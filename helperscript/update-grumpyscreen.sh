#!/bin/sh

# everything else in the script assumes its cloned to /usr/data/pellcorp
# so we must verify this or shit goes wrong
if [ "$(dirname $(readlink -f $0))" != "/usr/data/pellcorp/helperscript" ]; then
  >&2 echo "FATAL: This git repo must be cloned to /usr/data/pellcorp"
  exit 1
fi

/usr/data/helper-script/files/fixes/curl -L "https://github.com/pellcorp/grumpyscreen/releases/download/main/guppyscreen.tar.gz" -o /usr/data/guppyscreen.tar.gz
if [ $? -eq 0 ]; then
    tar xf /usr/data/guppyscreen.tar.gz -C /usr/data/ 2> /dev/null
    status=$?
    rm /usr/data/guppyscreen.tar.gz
    if [ $status -ne 0 ]; then
        echo "ERROR: GrumpyScreen could not be downloaded!"
        exit 0
    fi
else
    echo "ERROR: GrumpyScreen could not be downloaded!"
    exit 0
fi

# we want grumpyscreen.cfg to be editable from fluidd / mainsail we do that with a soft link
mv /usr/data/guppyscreen/grumpyscreen.cfg /usr/data/printer_data/config/
ln -sf /usr/data/printer_data/config/grumpyscreen.cfg /usr/data/guppyscreen/

sed -i 's/cooldown:.*/cooldown: SET_HEATER_TEMPERATURE HEATER=extruder TARGET=0/g' /usr/data/printer_data/config/grumpyscreen.cfg
sed -i 's/load_filament:.*/load_filament: _GUPPY_LOAD_MATERIAL EXTRUDER_TEMP={}/g' /usr/data/printer_data/config/grumpyscreen.cfg
sed -i 's/unload_filament:.*/unload_filament: _GUPPY_QUIT_MATERIAL EXTRUDER_TEMP={}/g' /usr/data/printer_data/config/grumpyscreen.cfg
sed -i 's~guppy_update_cmd:.*~guppy_update_cmd: /usr/data/pellcorp/helperscript/update-grumpyscreen.sh~g' /usr/data/printer_data/config/grumpyscreen.cfg
sed -i 's/switch_to_stock_cmd:.*/switch_to_stock_cmd:/g' /usr/data/printer_data/config/grumpyscreen.cfg
sed -i 's/support_zip_cmd:.*/support_zip_cmd:/g' /usr/data/printer_data/config/grumpyscreen.cfg

/etc/init.d/S99guppyscreen restart
