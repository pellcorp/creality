# Sources

The following files were originally from other projects.  Some of these files are verbatim copies, some of them have been locally modified.

- services/S50nginx_service -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/services/S50nginx_service
- services/S56moonraker_service -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/services/S56moonraker_service
- moonraker.conf -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/moonraker/moonraker.conf
- services/S55klipper_service -> https://raw.githubusercontent.com/K1-Klipper/installer_script_k1_and_max/main/S55klipper_service
- sensorless.cfg -> https://raw.githubusercontent.com/K1-Klipper/installer_script_k1_and_max/main/sensorless.cfg
- tools/curl -> https://raw.githubusercontent.com/ballaswag/k1-discovery/main/bin/curl
- tools/supervisorctl -> https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/fixes/supervisorctl
- tools/systemctl -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/fixes/systemctl
- tools/sudo -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/fixes/sudo
- mcu_util.py -> https://github.com/cryoz/k1_mcu_flasher/blob/master/mcu_util.py
- install-entware.sh -> https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/entware/generic.sh
- services/S13mcu_update -> https://github.com/Guilouz/Creality-K1-Extracted-Firmwares/blob/main/Firmware/etc/init.d/S13mcu_update
- services/S50webcam -> http://openk1.org/static/k1/scripts/multi-non-creality-webcams.sh
- cartographer_macro.cfg -> https://raw.githubusercontent.com/K1-Klipper/cartographer-klipper/master/cartographer_macro.cfg
- guppyscreen.cfg -> https://github.com/ballaswag/guppyscreen/blob/main/k1/scripts/guppy_cmd.cfg
- gcode_shell_command.py -> https://github.com/dw-0/kiauh/blob/master/resources/gcode_shell_command.py
- btteddy.cfg, btteddy_macro.cfg originally from -> https://github.com/ballaswag/creality_k1_klipper_mod/tree/master/printer_configs
- Smart_Park.cfg, Line_Purge.cfg originally from https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging
The nginx binaries originally came from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/nginx.tar.gz

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

## Helper Script

I have taken advantage of the fact helper script is open source to migrate some features from helper script to this project including:

- Some useful macros for fan control
- WARMUP macro

## Klipper

We are using my fork of klipper, which is mainline klipper, a fix for a temp sensor on the k1 and and a time out fix for bltouch, 
crtouch and microprobe to the mcu.py file.

### SSH Deploy Keys

I have issues with my internet and wifi in my workshop so often I get a timeout cloning the klipper repo, but there is
a way to use git ssh clone urls, its not ideal because moonraker can't use them but its just for testing, I generated the
ssh/identity key with:

```
dropbearkey -t ecdsa -f ~/.ssh/identity -s 256
```

I discovered how to do this from https://forum.archive.openwrt.org/viewtopic.php?id=47551

This mode is activated by prefixing the call to the installer with `KLIPPER_GIT_CLONE=ssh`, its not for normal use as
cloning via ssh is much slower than via curl but it does not seem to timeout.

## MCU Util

In the future I hope to use the mcu_util.py to do firmware updates, this relies on pyserial which is preinstalled on the k1.
