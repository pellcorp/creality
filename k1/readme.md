# Sources

The following files were originally from other projects.  Some of these files are verbatim copies, some of them have been locally modified.

- k1/services/S50nginx_service -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/services/S50nginx_service
- k1/services/S56moonraker_service -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/services/S56moonraker_service
- k1/moonraker.conf -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/moonraker/moonraker.conf
- k1/services/S55klipper_service -> https://raw.githubusercontent.com/K1-Klipper/installer_script_k1_and_max/main/S55klipper_service
- config/sensorless.cfg -> https://raw.githubusercontent.com/K1-Klipper/installer_script_k1_and_max/main/sensorless.cfg
- k1/tools/curl -> https://raw.githubusercontent.com/ballaswag/k1-discovery/main/bin/curl
- k1/tools/supervisorctl -> https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/fixes/supervisorctl
- k1/tools/systemctl -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/fixes/systemctl
- k1/tools/sudo -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/fixes/sudo
- k1/services/S13mcu_update -> https://github.com/Guilouz/Creality-K1-Extracted-Firmwares/blob/main/Firmware/etc/init.d/S13mcu_update
- k1/services/S50webcam -> http://openk1.org/static/k1/scripts/multi-non-creality-webcams.sh
- config/btteddy.cfg, config/btteddy_macro.cfg -> https://github.com/ballaswag/creality_k1_klipper_mod/tree/master/printer_configs
- config/Smart_Park.cfg, config/Line_Purge.cfg -> https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging

The k1/nginx.conf is originally from moonraker.tar.gz:nginx/nginx/nginx.conf, but I modified it locally to already
listen on port 80.

## Moonraker Env

The moonraker-env originally came from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

Use the `k1/scripts/recreate-moonraker-env.sh` script to extract the moonraker/moonraker-env directory from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

I have updated the env to install the asyncio and updated apprise packages locally to avoid doing that at installation time.
