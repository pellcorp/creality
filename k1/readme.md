# Sources

The following files were originally from other projects.  Some of these files are verbatim copies, some of them have been locally modified.

- services/S50nginx_service -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/services/S50nginx_service
- services/S56moonraker_service -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/services/S56moonraker_service
- moonraker.conf -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/moonraker/moonraker.conf
- services/S55klipper_service -> https://raw.githubusercontent.com/K1-Klipper/installer_script_k1_and_max/main/S55klipper_service
- sensorless.cfg -> https://raw.githubusercontent.com/K1-Klipper/installer_script_k1_and_max/main/sensorless.cfg
- tools/curl -> https://raw.githubusercontent.com/ballaswag/k1-discovery/main/bin/curl
- services/S58factoryreset -> https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/services/S58factoryreset
- tools/supervisorctl -> https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/fixes/supervisorctl
- mcu_util.py -> https://github.com/cryoz/k1_mcu_flasher/blob/master/mcu_util.py
- install-entware.sh -> https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/entware/generic.sh
- services/S13mcu_update -> https://github.com/Guilouz/Creality-K1-Extracted-Firmwares/blob/main/Firmware/etc/init.d/S13mcu_update
- services/S50webcam -> http://openk1.org/static/k1/scripts/multi-non-creality-webcams.sh
- cartographer/cartographer.py -> https://raw.githubusercontent.com/Cartographer3D/cartographer-klipper/master/cartographer.py
- cartographer/cartographer_macro.cfg -> https://raw.githubusercontent.com/K1-Klipper/cartographer-klipper/master/cartographer_macro.cfg

The nginx binaries originally came from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

Use the `scripts/recreate-nginx.sh` script to extract the nginx directory from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

The install/nginx.conf is originally from moonraker.tar.gz:nginx/nginx/nginx.conf, but I modified it locally to already
listen on port 80.

## Moonraker Env

The moonraker-env originally came from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

Use the `scripts/recreate-moonraker-env.sh` script to extract the moonraker/moonraker-env directory from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

I have updated the env to install the asyncio and updated apprise packages locally to avoid doing that at installation time.

## Klipper

We are using my fork of klipper, which is mainline klipper, a fix for a temp sensor on the k1 and and a time out fix for bltouch, 
crtouch and microprobe to the mcu.py file.

## MCU Firmware

the fw/K! firmware is built from my Klipper fork.

## Factory Reset

Although the latest version of S58factoryreset is copied from Guilouz, the original ideas was mine, and we worked on the
specifics and testing together, so to avoid any confusion I credited the fact I copied the final version from his repo,
but the latest code with minor changes came from me originally, just so we are clear :-)

## MCU Util

In the future I hope to use the mcu_util.py to do firmware updates, this relies on pyserial which is preinstalled on the k1.

## Pellcorp Python Env

scripts/recreate-pellcorp-env.sh is run on my k1-qemu environment and then I scp it back and merge it, 
less than ideal but I only need configupdater.

## Original Bootloader

I got a copy of the original nozzle bootloader from zarboz from discord, I have saved it here for reference.   Can be used
to restore a bricked MCU with stlink.

Refer to bootloader/Bootloader_GD32_ToolheadNozzle_Creality.bin

## Cartographer

I don't have a cartogropher, so I am making a best effort to introduce basic support for it, not really knowing exactly
what is required.
