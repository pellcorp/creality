#!/bin/ash

for file in guppy_config_helper.py calibrate_shaper_config.py guppy_module_loader.py tmcstatus.py; do
    ln -sf /usr/data/guppyscreen/k1_mods/$file /usr/data/klipper/klippy/extras/$file || exit $?
    if ! grep -q "klippy/extras/${file}" "/usr/data/klipper/.git/info/exclude"; then
        echo "klippy/extras/$file" >> "/usr/data/klipper/.git/info/exclude"
    fi
done
/usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy
