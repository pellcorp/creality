# Sources

The following files were originally from other projects.  Some of these files are verbatim copies, some of them have been locally modified.

- S50nginx_service -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/services/S50nginx_service
- S56moonraker_service -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/services/S56moonraker_service
- moonraker.conf -> https://github.com/Guilouz/Creality-Helper-Script/blob/main/files/moonraker/moonraker.conf
- S55klipper_service -> https://raw.githubusercontent.com/K1-Klipper/installer_script_k1_and_max/main/S55klipper_service
- sensorless.cfg -> https://raw.githubusercontent.com/K1-Klipper/installer_script_k1_and_max/main/sensorless.cfg
- curl -> https://raw.githubusercontent.com/ballaswag/k1-discovery/main/bin/curl
- S58factoryreset -> https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/services/S58factoryreset
- supervisorctl -> https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/fixes/supervisorctl

The nginx binaries originally came from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

Use the `recreate-nginx.sh` script to extract the nginx directory from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

The install/nginx.conf is originally from moonraker.tar.gz:nginx/nginx/nginx.conf, but I modified it locally to already
listen on port 80.

## Moonraker Env

The moonraker-env originally came from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

Use the `recreate-moonraker-env.sh` script to extract the moonraker/moonraker-env directory from:
https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz

I have updated the env to install the asyncio and updated apprise packages locally to avoid doing that at installation time.

## Klipper

We are using my fork of klipper, which is mainline klipper plus the fw/K1 files from http://github.com/k1-klipper/klipper
and a time out fix for bltouch, crtouch and microprobe to the mcu.cfg file.

## Factory Reset

Although the latest version of S58factoryreset is copied from Guilouz, the original ideas was mine, and we worked on the
specifics and testing together, so to avoid any confusion I credited the fact I copied the final version from his repo,
but the latest code with minor changes came from me originally, just so we are clear :-)
