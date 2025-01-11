#!/bin/sh

# this is really just for my k1-qemu environment
if [ ! -f /usr/data/printer_data/config/printer.cfg ]; then
  >&2 echo "ERROR: Printer data not setup"
  exit 1
fi

# 6. prefix is the prefix I use for pre-rooted firmware
ota_version=$(cat /etc/ota_info | grep ota_version | awk -F '=' '{print $2}' | sed 's/^6.//g' | tr -d '.')
if [ -z "$ota_version" ] || [ $ota_version -lt 1335 ]; then
  echo "ERROR: Firmware is too old, you must update to at least version 1.3.3.5 of Creality OS"
  echo "https://www.creality.com/pages/download-k1-flagship"
  exit 1
fi

MODEL=$(/usr/bin/get_sn_mac.sh model)
if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ] || [ "$MODEL" = "K1 SE" ]; then
  model=k1
elif [ "$MODEL" = "CR-K1 Max" ] || [ "$MODEL" = "K1 Max SE" ]; then
  model=k1m
else
  echo "This script is not supported for $MODEL!"
  exit 1
fi

if [ -d /usr/data/helper-script ] || [ -f /usr/data/fluidd.sh ] || [ -f /usr/data/mainsail.sh ]; then
    echo "The Guilouz helper and K1_Series_Annex scripts cannot be installed"
    exit 1
fi

# if we have not even started a new installation of simple af just double check there is no save config in the
# printer.cfg as this is a sure sign someone has forgot to do a factory reset
if [ -f /etc/init.d/S99start_app ]; then
    if grep -q "#*# <---------------------- SAVE_CONFIG ---------------------->" /usr/data/printer_data/config/printer.cfg; then
        echo "You must factory reset the printer before installing Simple AF!"
        exit 1
    fi
fi

# everything else in the script assumes its cloned to /usr/data/pellcorp
# so we must verify this or shit goes wrong
if [ "$(dirname $(readlink -f $0))" != "/usr/data/pellcorp/k1" ]; then
  >&2 echo "ERROR: This git repo must be cloned to /usr/data/pellcorp"
  exit 1
fi

# kill pip cache to free up overlayfs
rm -rf /root/.cache
sync

REMAINING_ROOT_DISK=$(df -m / | tail -1 | awk '{print $4}')
if [ $REMAINING_ROOT_DISK -gt 25 ]; then
    echo "INFO: There is $(df -h / | tail -1 | awk '{print $4}') remaining on your / partition"
else
    echo "CRITICAL: Remaining / space is critically low!"
    echo "CRITICAL: There is $(df -h / | tail -1 | awk '{print $4}') remaining on your / partition"
    exit 1
fi

REMAINING_TMP_DISK=$(df -m /tmp | tail -1 | awk '{print $4}')
if [ $REMAINING_TMP_DISK -gt 25 ]; then
    echo "INFO: There is $(df -h /tmp | tail -1 | awk '{print $4}') remaining on your /tmp partition"
else
    echo "CRITICAL: Remaining /tmp space is critically low!"
    echo "CRITICAL: There is $(df -h /tmp | tail -1 | awk '{print $4}') remaining on your /tmp partition"
    exit 1
fi

REMAINING_DATA_DISK=$(df -m /usr/data | tail -1 | awk '{print $4}')
if [ $REMAINING_DATA_DISK -gt 1000 ]; then
    echo "INFO: There is $(df -h /usr/data | tail -1 | awk '{print $4}') remaining on your /usr/data partition"
else
    echo "CRITICAL: Remaining disk space is critically low!"
    echo "CRITICAL: There is $(df -h /usr/data | tail -1 | awk '{print $4}') remaining on your /usr/data partition"
    exit 1
fi
echo

cp /usr/data/pellcorp/k1/services/S45cleanup /etc/init.d || exit $?
cp /usr/data/pellcorp/k1/services/S58factoryreset /etc/init.d || exit $?
cp /usr/data/pellcorp/k1/services/S50dropbear /etc/init.d/ || exit $?
sync

# for k1 the installed curl does not do ssl, so we replace it first
# and we can then make use of it going forward
cp /usr/data/pellcorp/k1/tools/curl /usr/bin/curl || exit $?
sync

CONFIG_HELPER="/usr/data/pellcorp/k1/config-helper.py"

# thanks to @Nestaa51 for the timeout changes to not wait forever for moonraker
function restart_moonraker() {
    echo
    echo "INFO: Restarting Moonraker ..."
    /etc/init.d/S56moonraker_service restart

    timeout=60
    start_time=$(date +%s)

    # this is mostly for k1-qemu where Moonraker takes a while to start up
    echo "INFO: Waiting for Moonraker ..."
    while true; do
        KLIPPER_PATH=$(curl localhost:7125/printer/info 2> /dev/null | jq -r .result.klipper_path)
        # moonraker will start reporting the location of klipper as /usr/data/klipper when using a soft link
        if [ "$KLIPPER_PATH" = "/usr/share/klipper" ] || [ "$KLIPPER_PATH" = "/usr/data/klipper" ]; then
            break;
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            break;
        fi
        sleep 1
    done
}

function update_repo() {
    local repo_dir=$1
    local branch=$2

    if [ -d "${repo_dir}/.git" ]; then
        cd $repo_dir
        branch_ref=$(git rev-parse --abbrev-ref HEAD)
        if [ -n "$branch_ref" ]; then
            git fetch

            if [ -z "$branch" ]; then
                git reset --hard origin/$branch_ref
            else
                git switch $branch
                if [ $? -eq 0 ]; then
                  git reset --hard origin/$branch
                fi
            fi
            cd - > /dev/null
            sync
        else
            cd - > /dev/null
            echo "Failed to detect current branch!"
            return 1
        fi
    else
        echo "Invalid $repo_dir specified"
        return 1
    fi
    return 0
}

function update_klipper() {
  if [ -d /usr/data/cartographer-klipper ]; then
      /usr/data/cartographer-klipper/install.sh || return $?
      sync
  fi
  if [ -d /usr/data/beacon-klipper ]; then
      /usr/data/pellcorp/k1/beacon-install.sh || return $?
      sync
  fi
  /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || return $?
  /usr/data/pellcorp/k1/tools/check-firmware.sh --status
  if [ $? -eq 0 ]; then
      echo "INFO: Restarting Klipper ..."
      /etc/init.d/S55klipper_service restart
  fi
  return $?
}

function install_config_updater() {
    python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Installing configupdater python package ..."
        pip3 install configupdater==3.2

        python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
        if [ $? -ne 0 ]; then
            echo "ERROR: Something bad happened, can't continue"
            exit 1
        fi
    fi

    # old pellcorp-env not required anymore
    if [ -d /usr/data/pellcorp-env/ ]; then
        rm -rf /usr/data/pellcorp-env/
    fi
    sync
}

function disable_creality_services() {
    if [ ! -L /etc/boot-display/part0 ]; then
      # clean up failed installation of custom boot display
      rm -rf /overlay/upper/etc/boot-display/*
      rm -rf /overlay/upper/etc/logo/*
      rm -f /overlay/upper/etc/init.d/S12boot_display
      rm -f /overlay/upper/etc/init.d/S11jpeg_display_shell
      mount -o remount /
    fi

    if [ -f /etc/init.d/S99start_app ]; then
        echo
        echo "INFO: Disabling some creality services ..."

        # remove the old gcode files provided by creality as they should not be printed
        if [ -d /usr/data/printer_data/gcodes/ ]; then
            rm /usr/data/printer_data/gcodes/*.gcode
        fi

        if [ -f /etc/init.d/S99start_app ]; then
            echo "INFO: If you reboot the printer before installing guppyscreen, the screen will be blank - this is to be expected!"
            /etc/init.d/S99start_app stop > /dev/null 2>&1
            rm /etc/init.d/S99start_app
        fi
        if [ -f /etc/init.d/S70cx_ai_middleware ]; then
            /etc/init.d/S70cx_ai_middleware stop > /dev/null 2>&1
            rm /etc/init.d/S70cx_ai_middleware
        fi
        if [ -f /etc/init.d/S97webrtc ]; then
            /etc/init.d/S97webrtc stop > /dev/null 2>&1
            rm /etc/init.d/S97webrtc
        fi
        if [ -f /etc/init.d/S99mdns ]; then
            /etc/init.d/S99mdns stop > /dev/null 2>&1
            rm /etc/init.d/S99mdns
        fi
        if [ -f /etc/init.d/S96wipe_data ]; then
            wipe_data_pid=$(ps -ef | grep wipe_data | grep -v "grep" | awk '{print $1}')
            if [ -n "$wipe_data_pid" ]; then
                kill -9 $wipe_data_pid
            fi
            rm /etc/init.d/S96wipe_data
        fi
        if [ -f /etc/init.d/S55klipper_service ]; then
            /etc/init.d/S55klipper_service stop > /dev/null 2>&1
        fi

        if [ -f /etc/init.d/S57klipper_mcu ]; then
            /etc/init.d/S57klipper_mcu stop > /dev/null 2>&1
            rm /etc/init.d/S57klipper_mcu
        fi

        # the log main process takes up so much memory a lot of it swapped, killing this process might make the
        # installer go a little more quickly as there is no swapping going on
        log_main_pid=$(ps -ef | grep log_main | grep -v "grep" | awk '{print $1}')
        if [ -n "$log_main_pid" ]; then
            kill -9 $log_main_pid
        fi
    fi

    # this is mostly backwards compatible
    if [ -f /etc/init.d/S57klipper_mcu ]; then
        /etc/init.d/S55klipper_service stop > /dev/null 2>&1
        /etc/init.d/S57klipper_mcu stop > /dev/null 2>&1
        rm /etc/init.d/S57klipper_mcu
    fi

    sync
}

function install_boot_display() {
  grep -q "boot-display" /usr/data/pellcorp.done
  if [ $? -ne 0 ]; then
    echo
    echo "INFO: Installing custom boot display ..."

    # shamelessly stolen from https://github.com/Guilouz/Creality-Helper-Script/blob/main/scripts/custom_boot_display.sh
    rm -rf /etc/boot-display/part0
    cp /usr/data/pellcorp/k1/boot-display.conf /etc/boot-display/
    cp /usr/data/pellcorp/k1/services/S11jpeg_display_shell /etc/init.d/
    mkdir -p /usr/data/boot-display
    tar -zxf "/usr/data/pellcorp/k1/boot-display.tar.gz" -C /usr/data/boot-display
    ln -s /usr/data/boot-display/part0 /etc/boot-display/
    echo "boot-display" >> /usr/data/pellcorp.done
    sync
    return 1
  fi
  return 0
}

function install_webcam() {
    local mode=$1
    
    grep -q "webcam" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] || [ ! -f /opt/bin/mjpg_streamer ]; then
            echo
            echo "INFO: Installing mjpg streamer ..."
            /opt/bin/opkg install mjpg-streamer mjpg-streamer-input-http mjpg-streamer-input-uvc mjpg-streamer-output-http mjpg-streamer-www || exit $?
        fi

        echo "INFO: Updating webcam config ..."
        # we do not want to start the entware version of the service ever
        if [ -f /opt/etc/init.d/S96mjpg-streamer ]; then
            rm /opt/etc/init.d/S96mjpg-streamer
        fi
        # kill the existing creality services so that we can use the app right away without a restart
        pidof cam_app &>/dev/null && killall -TERM cam_app > /dev/null 2>&1
        pidof mjpg_streamer &>/dev/null && killall -TERM mjpg_streamer > /dev/null 2>&1

        if [ -f /etc/init.d/S50webcam ]; then
            /etc/init.d/S50webcam stop > /dev/null 2>&1
        fi

        # auto_uvc.sh is responsible for starting the web cam_app
        [ -f /usr/bin/auto_uvc.sh ] && rm /usr/bin/auto_uvc.sh
        cp /usr/data/pellcorp/k1/files/auto_uvc.sh /usr/bin/
        chmod 777 /usr/bin/auto_uvc.sh

        cp /usr/data/pellcorp/k1/services/S50webcam /etc/init.d/
        /etc/init.d/S50webcam start

        if [ -f /usr/data/pellcorp.ipaddress ]; then
          # don't wipe the pellcorp.ipaddress if its been explicitly set to skip
          PREVIOUS_IP_ADDRESS=$(cat /usr/data/pellcorp.ipaddress 2> /dev/null)
          if [ "$PREVIOUS_IP_ADDRESS" != "skip" ]; then
            rm /usr/data/pellcorp.ipaddress
          fi
        fi
        cp /usr/data/pellcorp/k1/webcam.conf /usr/data/printer_data/config/ || exit $?

        echo "webcam" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function install_moonraker() {
    local mode=$1

    grep -q "moonraker" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        
        if [ "$mode" != "update" ] && [ -d /usr/data/moonraker ]; then
            if [ -f /etc/init.d/S56moonraker_service ]; then
                /etc/init.d/S56moonraker_service stop
            fi
            if [ -d /usr/data/printer_data/database/ ]; then
                [ -f /usr/data/moonraker-database.tar.gz ] && rm /usr/data/moonraker-database.tar.gz

                echo "INFO: Backing up moonraker database ..."
                cd /usr/data/printer_data/

                tar -zcf /usr/data/moonraker-database.tar.gz database/
                cd 
            fi
            rm -rf /usr/data/moonraker
        fi

        if [ "$mode" != "update" ] && [ -d /usr/data/moonraker-env ]; then
            rm -rf /usr/data/moonraker-env
        fi

        if [ ! -d /usr/data/moonraker/.git ]; then
            echo "INFO: Installing moonraker ..."
        
            [ -d /usr/data/moonraker ] && rm -rf /usr/data/moonraker
            [ -d /usr/data/moonraker-env ] && rm -rf /usr/data/moonraker-env

            echo
            git clone https://github.com/Arksine/moonraker /usr/data/moonraker || exit $?

            if [ -f /usr/data/moonraker-database.tar.gz ]; then
                echo
                echo "INFO: Restoring moonraker database ..."
                cd /usr/data/printer_data/
                tar -zxf /usr/data/moonraker-database.tar.gz
                rm /usr/data/moonraker-database.tar.gz
                cd
            fi
        fi

        if [ ! -f /usr/data/moonraker-timelapse/component/timelapse.py ]; then
            if [ -d /usr/data/moonraker-timelapse ]; then
                rm -rf /usr/data/moonraker-timelapse
            fi
            git clone https://github.com/mainsail-crew/moonraker-timelapse.git /usr/data/moonraker-timelapse/ || exit $?
        fi

        if [ ! -d /usr/data/moonraker-env ]; then
            tar -zxf /usr/data/pellcorp/k1/moonraker-env.tar.gz -C /usr/data/ || exit $?
        fi

        if [ "$mode" != "update" ] || [ ! -f /opt/bin/ffmpeg ]; then
            echo "INFO: Upgrading ffmpeg for moonraker timelapse ..."
            /opt/bin/opkg install ffmpeg || exit $?
        fi

        echo "INFO: Updating moonraker config ..."

        # an existing bug where the moonraker secrets was not correctly copied
        if [ ! -f /usr/data/printer_data/moonraker.secrets ]; then
            cp /usr/data/pellcorp/k1/moonraker.secrets /usr/data/printer_data/
        fi

        ln -sf /usr/data/pellcorp/k1/tools/supervisorctl /usr/bin/ || exit $?
        ln -sf /usr/data/pellcorp/k1/tools/systemctl /usr/bin/ || exit $?
        ln -sf /usr/data/pellcorp/k1/tools/sudo /usr/bin/ || exit $?
        cp /usr/data/pellcorp/k1/services/S56moonraker_service /etc/init.d/ || exit $?
        cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/ || exit $?
        ln -sf /usr/data/pellcorp/k1/moonraker.asvc /usr/data/printer_data/ || exit $?

        ln -sf /usr/data/moonraker-timelapse/component/timelapse.py /usr/data/moonraker/moonraker/components/ || exit $?
        if ! grep -q "moonraker/components/timelapse.py" "/usr/data/moonraker/.git/info/exclude"; then
            echo "moonraker/components/timelapse.py" >> "/usr/data/moonraker/.git/info/exclude"
        fi
        ln -sf /usr/data/moonraker-timelapse/klipper_macro/timelapse.cfg /usr/data/printer_data/config/ || exit $?
        cp /usr/data/pellcorp/k1/timelapse.conf /usr/data/printer_data/config/ || exit $?

        # after an initial install do not overwrite notifier.conf or moonraker.secrets
        if [ ! -f /usr/data/printer_data/config/notifier.conf ]; then
            cp /usr/data/pellcorp/k1/notifier.conf /usr/data/printer_data/config/ || exit $?
        fi
        if [ ! -f /usr/data/printer_data/moonraker.secrets ]; then
            cp /usr/data/pellcorp/k1/moonraker.secrets /usr/data/printer_data/ || exit $?
        fi

        echo "moonraker" >> /usr/data/pellcorp.done
        sync

        # means nginx and moonraker need to be restarted
        return 1
    fi
    return 0
}

function install_nginx() {
    local mode=$1

    grep -q "nginx" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        default_ui=fluidd
        if [ -f /usr/data/nginx/nginx/sites/mainsail ]; then
          grep "#listen" /usr/data/nginx/nginx/sites/mainsail > /dev/null
          if [ $? -ne 0 ]; then
            default_ui=mainsail
          fi
        fi

        if [ "$mode" != "update" ] && [ -d /usr/data/nginx ]; then
            if [ -f /etc/init.d/S50nginx_service ]; then
                /etc/init.d/S50nginx_service stop
            fi
            rm -rf /usr/data/nginx
        fi

        if [ ! -d /usr/data/nginx ]; then
            echo
            echo "INFO: Installing nginx ..."

            tar -zxf /usr/data/pellcorp/k1/nginx.tar.gz -C /usr/data/ || exit $?
        fi

        echo "INFO: Updating nginx config ..."
        cp /usr/data/pellcorp/k1/nginx.conf /usr/data/nginx/nginx/ || exit $?
        mkdir -p /usr/data/nginx/nginx/sites/
        cp /usr/data/pellcorp/k1/nginx/fluidd /usr/data/nginx/nginx/sites/ || exit $?
        cp /usr/data/pellcorp/k1/nginx/mainsail /usr/data/nginx/nginx/sites/ || exit $?

        if [ "$default_ui" = "mainsail" ]; then
          echo "INFO: Restoring mainsail as default UI"
          sed -i 's/.*listen 80 default_server;/    #listen 80 default_server;/g' /usr/data/nginx/nginx/sites/fluidd || exit $?
          sed -i 's/.*#listen 80 default_server;/    listen 80 default_server;/g' /usr/data/nginx/nginx/sites/mainsail || exit $?
        fi

        cp /usr/data/pellcorp/k1/services/S50nginx_service /etc/init.d/ || exit $?

        echo "nginx" >> /usr/data/pellcorp.done
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

function install_fluidd() {
    local mode=$1

    grep -q "fluidd" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/fluidd ]; then
            rm -rf /usr/data/fluidd
        fi
        if [ "$mode" != "update" ] && [ -d /usr/data/fluidd-config ]; then
            rm -rf /usr/data/fluidd-config
        fi

        if [ ! -d /usr/data/fluidd ]; then
            echo
            echo "INFO: Installing fluidd ..."

            mkdir -p /usr/data/fluidd || exit $?
            curl -L "https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip" -o /usr/data/fluidd.zip || exit $?
            unzip -qd /usr/data/fluidd /usr/data/fluidd.zip || exit $?
            rm /usr/data/fluidd.zip
        fi
        
        if [ ! -d /usr/data/fluidd-config ]; then
            git clone https://github.com/fluidd-core/fluidd-config.git /usr/data/fluidd-config || exit $?
        fi

        echo "INFO: Updating fluidd config ..."
        [ -f /usr/data/printer_data/config/fluidd.cfg ] && rm /usr/data/printer_data/config/fluidd.cfg

        ln -sf /usr/data/fluidd-config/client.cfg /usr/data/printer_data/config/fluidd.cfg

        # for moonraker to be able to use moonraker fluidd client.cfg out of the box need to
        ln -sf /usr/data/printer_data/ /root

        # these are already defined in fluidd config so get rid of them from printer.cfg
        $CONFIG_HELPER --remove-section "pause_resume" || exit $?
        $CONFIG_HELPER --remove-section "display_status" || exit $?
        $CONFIG_HELPER --remove-section "virtual_sdcard" || exit $?

        $CONFIG_HELPER --replace-section-entry "filament_switch_sensor filament_sensor" "runout_gcode" "_ON_FILAMENT_RUNOUT" || exit $?

        $CONFIG_HELPER --add-include "fluidd.cfg" || exit $?

        echo "fluidd" >> /usr/data/pellcorp.done
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

function install_mainsail() {
    local mode=$1

    grep -q "mainsail" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/mainsail ]; then
            rm -rf /usr/data/mainsail
        fi

        if [ ! -d /usr/data/mainsail ]; then
            echo
            echo "INFO: Installing mainsail ..."

            mkdir -p /usr/data/mainsail || exit $?
            curl -L "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o /usr/data/mainsail.zip || exit $?
            unzip -qd /usr/data/mainsail /usr/data/mainsail.zip || exit $?
            rm /usr/data/mainsail.zip
        fi

        echo "INFO: Updating mainsail config ..."

        # the mainsail and fluidd client.cfg are exactly the same
        [ -f /usr/data/printer_data/config/mainsail.cfg ] && rm /usr/data/printer_data/config/mainsail.cfg

        echo "mainsail" >> /usr/data/pellcorp.done
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

function install_kamp() {
    local mode=$1

    grep -q "KAMP" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/KAMP ]; then
            rm -rf /usr/data/KAMP
        fi
        
        if [ ! -d /usr/data/KAMP/.git ]; then
            echo
            echo "INFO: Installing KAMP ..."
            [ -d /usr/data/KAMP ] && rm -rf /usr/data/KAMP

            if [ "$AF_GIT_CLONE" = "ssh" ]; then
                export GIT_SSH_IDENTITY=KAMP
                export GIT_SSH=/usr/data/pellcorp/k1/ssh/git-ssh.sh
                git clone git@github.com:pellcorp/Klipper-Adaptive-Meshing-Purging.git /usr/data/KAMP || exit $?
                cd /usr/data/KAMP && git remote set-url origin https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git && cd - > /dev/null
            else
                git clone https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git /usr/data/KAMP || exit $?
            fi
        fi

        echo "INFO: Updating KAMP config ..."
        ln -sf /usr/data/KAMP/Configuration /usr/data/printer_data/config/KAMP || exit $?

        cp /usr/data/KAMP/Configuration/KAMP_Settings.cfg /usr/data/printer_data/config/ || exit $?

        $CONFIG_HELPER --add-include "KAMP_Settings.cfg" || exit $?

        # LINE_PURGE
        sed -i 's:#\[include ./KAMP/Line_Purge.cfg\]:\[include ./KAMP/Line_Purge.cfg\]:g' /usr/data/printer_data/config/KAMP_Settings.cfg

        # SMART_PARK
        sed -i 's:#\[include ./KAMP/Smart_Park.cfg\]:\[include ./KAMP/Smart_Park.cfg\]:g' /usr/data/printer_data/config/KAMP_Settings.cfg

        # lower and longer purge line
        $CONFIG_HELPER --file KAMP_Settings.cfg --replace-section-entry "gcode_macro _KAMP_Settings" variable_purge_height 0.5
        $CONFIG_HELPER --file KAMP_Settings.cfg --replace-section-entry "gcode_macro _KAMP_Settings" variable_purge_amount 48

        cp /usr/data/printer_data/config/KAMP_Settings.cfg /usr/data/pellcorp-backups/

        echo "KAMP" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function cleanup_klipper() {
    if [ -f /etc/init.d/S55klipper_service ]; then
        /etc/init.d/S55klipper_service stop
    fi
    rm -rf /usr/data/klipper

    # a reinstall should reset the choice of what klipper to run
    if [ -f /usr/data/pellcorp.klipper ]; then
      rm /usr/data/pellcorp.klipper
    fi
}

function install_klipper() {
    local mode=$1
    local probe=$2

    grep -q "klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo

        klipper_repo=klipper
        existing_klipper_repo=$(cat /usr/data/pellcorp.klipper 2> /dev/null)
        if [ "$mode" = "update" ] && [ "$existing_klipper_repo" = "k1-carto-klipper" ]; then
            echo "INFO: Forcing Klipper repo to be switched from pellcorp/${existing_klipper_repo} to pellcorp/${klipper_repo}"
            cleanup_klipper
        elif [ "$mode" != "update" ] && [ -d /usr/data/klipper ]; then
            cleanup_klipper
        fi

        # switch to required klipper version except where there is a flag file indicating we explicitly
        # decided to use a particular version of klipper
        if [ -d /usr/data/klipper/.git ] && [ ! -f /usr/data/pellcorp.klipper ]; then
            cd /usr/data/klipper/
            remote_repo=$(git remote get-url origin | awk -F '/' '{print $NF}' | sed 's/.git//g')
            cd - > /dev/null
            if [ "$remote_repo" != "$klipper_repo" ]; then
                echo "INFO: Forcing Klipper repo to be switched from pellcorp/${remote_repo} to pellcorp/${klipper_repo}"
                rm -rf /usr/data/klipper/
            fi
        fi

        if [ ! -d /usr/data/klipper/.git ]; then
            echo "INFO: Installing ${klipper_repo} ..."

            if [ "$AF_GIT_CLONE" = "ssh" ]; then
                export GIT_SSH_IDENTITY=${klipper_repo}
                export GIT_SSH=/usr/data/pellcorp/k1/ssh/git-ssh.sh
                git clone git@github.com:pellcorp/${klipper_repo}.git /usr/data/klipper || exit $?
                # reset the origin url to make moonraker happy
                cd /usr/data/klipper && git remote set-url origin https://github.com/pellcorp/${klipper_repo}.git && cd - > /dev/null
            else
                git clone https://github.com/pellcorp/${klipper_repo}.git /usr/data/klipper || exit $?
            fi
            [ -d /usr/share/klipper ] && rm -rf /usr/share/klipper
        else
            cd /usr/data/klipper/
            remote_repo=$(git remote get-url origin | awk -F '/' '{print $NF}' | sed 's/.git//g')
            last_revision_date=$(git log -1 --format="%at" | xargs -I{} date -d @{} +%Y%m%d)
            cd - > /dev/null

            # force update of klipper to one with TMPDIR support
            if [ "$remote_repo" = "klipper" ] && [ $last_revision_date -lt 20250111 ]; then
                echo "INFO: Forcing update of klipper to latest master"
                update_repo /usr/data/klipper master || exit $?
            fi
        fi

        echo "INFO: Updating klipper config ..."
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        # FIXME - one day maybe we can get rid of this link
        ln -sf /usr/data/klipper /usr/share/ || exit $?

        # for scripts like ~/klipper/scripts, a soft link makes things a little bit easier
        ln -sf /usr/data/klipper/ /root

        cp /usr/data/pellcorp/k1/services/S55klipper_service /etc/init.d/ || exit $?

        cp /usr/data/pellcorp/k1/services/S13mcu_update /etc/init.d/ || exit $?

        cp /usr/data/pellcorp/k1/sensorless.cfg /usr/data/printer_data/config/ || exit $?

        cp /usr/data/pellcorp/k1/useful_macros.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "useful_macros.cfg" || exit $?

        # the klipper_mcu is not even used, so just get rid of it
        $CONFIG_HELPER --remove-section "mcu rpi" || exit $?

        $CONFIG_HELPER --remove-section "bl24c16f" || exit $?
        $CONFIG_HELPER --remove-section "prtouch_v2" || exit $?
        $CONFIG_HELPER --remove-section "mcu leveling_mcu" || exit $?
        $CONFIG_HELPER --remove-section "output_pin power" || exit $?
        $CONFIG_HELPER --remove-section-entry "printer" "square_corner_max_velocity" || exit $?
        $CONFIG_HELPER --remove-section-entry "printer" "max_accel_to_decel" || exit $?

        # https://www.klipper3d.org/TMC_Drivers.html#prefer-to-not-specify-a-hold_current
        $CONFIG_HELPER --remove-section-entry "tmc2209 stepper_x" "hold_current" || exit $?
        $CONFIG_HELPER --remove-section-entry "tmc2209 stepper_y" "hold_current" || exit $?

        $CONFIG_HELPER --remove-include "printer_params.cfg" || exit $?
        $CONFIG_HELPER --remove-include "gcode_macro.cfg" || exit $?
        $CONFIG_HELPER --remove-include "custom_gcode.cfg" || exit $?

        if [ -f /usr/data/printer_data/config/custom_gcode.cfg ]; then
            rm /usr/data/printer_data/config/custom_gcode.cfg
        fi

        if [ -f /usr/data/printer_data/config/gcode_macro.cfg ]; then
            rm /usr/data/printer_data/config/gcode_macro.cfg
        fi

        if [ -f /usr/data/printer_data/config/printer_params.cfg ]; then
            rm /usr/data/printer_data/config/printer_params.cfg
        fi

        if [ -f /usr/data/printer_data/config/factory_printer.cfg ]; then
            rm /usr/data/printer_data/config/factory_printer.cfg
        fi

        cp /usr/data/pellcorp/k1/start_end.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "start_end.cfg" || exit $?
        if [ "$MODEL" = "K1 SE" ]; then
            sed -i '/SET_FAN_SPEED FAN=chamber.*/d' /usr/data/printer_data/config/start_end.cfg
        fi

        cp /usr/data/pellcorp/k1/fan_control.cfg /usr/data/printer_data/config || exit $?
        $CONFIG_HELPER --add-include "fan_control.cfg" || exit $?

        # K1 SE has no chamber fan
        if [ "$MODEL" = "K1 SE" ]; then
            sed -i '/SET_FAN_SPEED FAN=chamber.*/d' /usr/data/printer_data/config/fan_control.cfg
            $CONFIG_HELPER --file fan_control.cfg --remove-section "gcode_macro M191" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --remove-section "gcode_macro M141" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --remove-section "temperature_sensor chamber_temp" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --remove-section "temperature_fan chamber_fan" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --remove-section "fan_generic chamber" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --replace-section-entry "duplicate_pin_override" "pins" "PC5" || exit $?
        fi

        $CONFIG_HELPER --remove-section "output_pin fan0" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan1" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan2" || exit $?

        # a few strange duplicate pins appear in some firmware
        $CONFIG_HELPER --remove-section "output_pin PA0" || exit $?
        $CONFIG_HELPER --remove-section "output_pin PB2" || exit $?
        $CONFIG_HELPER --remove-section "output_pin PB10" || exit $?
        $CONFIG_HELPER --remove-section "output_pin PC8" || exit $?
        $CONFIG_HELPER --remove-section "output_pin PC9" || exit $?
        
        # duplicate pin can only be assigned once, so we remove it from printer.cfg so we can
        # configure it in fan_control.cfg
        $CONFIG_HELPER --remove-section "duplicate_pin_override" || exit $?
        
        # no longer required as we configure the part fan entirely in fan_control.cfg
        $CONFIG_HELPER --remove-section "static_digital_output my_fan_output_pins" || exit $?

        # moving the heater_fan to fan_control.cfg
        $CONFIG_HELPER --remove-section "heater_fan hotend_fan" || exit $?

        # all the fans and temp sensors are going to fan control now
        $CONFIG_HELPER --remove-section "temperature_sensor mcu_temp" || exit $?
        $CONFIG_HELPER --remove-section "temperature_sensor chamber_temp" || exit $?
        $CONFIG_HELPER --remove-section "temperature_fan chamber_fan" || exit $?

        # just in case anyone manually has added this to printer.cfg
        $CONFIG_HELPER --remove-section "temperature_fan mcu_fan" || exit $?

        # the nozzle should not trigger the MCU anymore        
        $CONFIG_HELPER --remove-section "multi_pin heater_fans" || exit $?

        # moving idle timeout to start_end.cfg so we can have some integration with
        # start and end print and warp stabilisation if needed
        $CONFIG_HELPER --remove-section "idle_timeout" || exit $?

        # just in case its missing from stock printer.cfg make sure it gets added
        $CONFIG_HELPER --add-section "exclude_object" || exit $?

        echo "klipper" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function install_guppyscreen() {
    local mode=$1

    grep -q "guppyscreen" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/guppyscreen ]; then
            if [ -f /etc/init.d/S99guppyscreen ]; then
              /etc/init.d/S99guppyscreen stop  > /dev/null 2>&1
              killall -q guppyscreen > /dev/null 2>&1
            fi
            rm -rf /usr/data/guppyscreen
        fi

        # check for non pellcorp guppyscreen and force an update
        if [ ! -f /usr/data/guppyscreen/guppyscreen.json ]; then
            echo
            echo "INFO: Forcing update of guppyscreen"
            rm -rf /usr/data/guppyscreen
        elif grep -q "log_path" /usr/data/guppyscreen/guppyscreen.json; then
            echo
            echo "INFO: Forcing update of guppyscreen"
            rm -rf /usr/data/guppyscreen
        fi

        if [ ! -d /usr/data/guppyscreen ]; then
            echo
            echo "INFO: Installing guppyscreen ..."

            curl -L "https://github.com/pellcorp/guppyscreen/releases/download/nightly/guppyscreen.tar.gz" -o /usr/data/guppyscreen.tar.gz || exit $?
            tar xf /usr/data/guppyscreen.tar.gz -C /usr/data/ || exit $?
            rm /usr/data/guppyscreen.tar.gz 
        fi

        echo "INFO: Updating guppyscreen config ..."
        cp /usr/data/pellcorp/k1/services/S99guppyscreen /etc/init.d/ || exit $?

        if [ ! -d "/usr/lib/python3.8/site-packages/matplotlib-2.2.3-py3.8.egg-info" ]; then
            echo "WARNING: Not replacing mathplotlib ft2font module. PSD graphs might not work!"
        else
            cp /usr/data/pellcorp/k1/fixes/ft2font.cpython-38-mipsel-linux-gnu.so /usr/lib/python3.8/site-packages/matplotlib/ || exit $?
        fi

        # remove all excludes from guppyscreen
        for file in gcode_shell_command.py guppy_config_helper.py calibrate_shaper_config.py guppy_module_loader.py tmcstatus.py; do
            if grep -q "klippy/extras/${file}" "/usr/data/klipper/.git/info/exclude"; then
                sed -i "/klippy\/extras\/$file$/d" "/usr/data/klipper/.git/info/exclude"
            fi
        done
        
        # get rid of the old guppyscreen config
        [ -d /usr/data/printer_data/config/GuppyScreen ] && rm -rf /usr/data/printer_data/config/GuppyScreen

        cp /usr/data/pellcorp/k1/guppyscreen.cfg /usr/data/printer_data/config/ || exit $?

        # a single local guppyscreen.cfg which references the python files from /usr/data/guppyscreen instead
        $CONFIG_HELPER --remove-include "GuppyScreen/*.cfg" || exit $?

        $CONFIG_HELPER --add-include "guppyscreen.cfg" || exit $?

        echo "guppyscreen" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function setup_probe() {
    grep -q "probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up generic probe config ..."

        $CONFIG_HELPER --remove-section "bed_mesh" || exit $?
        $CONFIG_HELPER --remove-section-entry "stepper_z" "position_endstop" || exit $?
        $CONFIG_HELPER --replace-section-entry "stepper_z" "endstop_pin" "probe:z_virtual_endstop" || exit $?

        cp /usr/data/pellcorp/k1/quickstart.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "quickstart.cfg" || exit $?

        # because we are using force move with 3mm, as a safety feature we will lower the position max
        # by 3mm ootb to avoid damaging the printer if you do a really big print
        position_max=$($CONFIG_HELPER --get-section-entry "stepper_z" "position_max")
        position_max=$((position_max-3))
        $CONFIG_HELPER --replace-section-entry "stepper_z" "position_max" "$position_max" || exit $?

        echo "probe" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function install_cartographer_klipper() {
    local mode=$1

    grep -q "cartographer-klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/cartographer-klipper ]; then
            rm -rf /usr/data/cartographer-klipper
        fi

        if [ ! -d /usr/data/cartographer-klipper ]; then
            echo
            echo "INFO: Installing cartographer-klipper ..."
            git clone https://github.com/pellcorp/cartographer-klipper.git /usr/data/cartographer-klipper || exit $?
        else
            cd /usr/data/cartographer-klipper
            REMOTE_URL=$(git remote get-url origin)
            if [ "$REMOTE_URL" != "https://github.com/pellcorp/cartographer-klipper.git" ]; then
                echo "INFO: Switching cartographer-klipper to pellcorp fork"
                git remote set-url origin https://github.com/pellcorp/cartographer-klipper.git
                git fetch origin
            fi

            branch=$(git rev-parse --abbrev-ref HEAD)
            # do not stuff up a different branch
            if [ "$branch" = "master" ]; then
                revision=$(git rev-parse --short HEAD)
                # reset our branch or update from v1.0.5
                if [ "$revision" = "303ea63" ] || [ "$revision" = "8324877" ]; then
                    echo "INFO: Forcing cartographer-klipper update"
                    git fetch origin
                    git reset --hard v1.1.0
                fi
            fi
        fi
        cd - > /dev/null

        echo
        echo "INFO: Running cartographer-klipper installer ..."
        bash /usr/data/cartographer-klipper/install.sh || exit $?
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        echo "cartographer-klipper" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function install_beacon_klipper() {
    local mode=$1

    grep -q "beacon-klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/beacon-klipper ]; then
            rm -rf /usr/data/beacon-klipper
        fi

        if [ ! -d /usr/data/beacon-klipper ]; then
            echo
            echo "INFO: Installing beacon-klipper ..."
            git clone https://github.com/beacon3d/beacon_klipper /usr/data/beacon-klipper || exit $?
        fi

        # FIXME - maybe beacon will accept a PR to make their installer work on k1
        /usr/data/pellcorp/k1/beacon-install.sh

        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        echo "beacon-klipper" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function cleanup_probe() {
    local probe=$1

    if [ -f /usr/data/printer_data/config/${probe}_macro.cfg ]; then
        rm /usr/data/printer_data/config/${probe}_macro.cfg
    fi
    $CONFIG_HELPER --remove-include "${probe}_macro.cfg" || exit $?

    if [ "$probe" = "cartotouch" ] || [ "$probe" = "beacon" ]; then
        $CONFIG_HELPER --remove-section-entry "stepper_z" "homing_retract_dist" || exit $?
    fi

    if [ -f /usr/data/printer_data/config/$probe.cfg ]; then
        rm /usr/data/printer_data/config/$probe.cfg
    fi
    $CONFIG_HELPER --remove-include "$probe.cfg" || exit $?

    # we use the cartographer includes
    if [ "$probe" = "cartotouch" ]; then
        probe=cartographer
    fi

    if [ -f /usr/data/printer_data/config/${probe}.conf ]; then
        rm /usr/data/printer_data/config/${probe}.conf
    fi

    # if switching from btt eddy remove this file
    if [ "$probe" = "btteddy" ] && [ -f /usr/data/printer_data/config/variables.cfg ]; then
        rm /usr/data/printer_data/config/variables.cfg
    fi

    $CONFIG_HELPER --file moonraker.conf --remove-include "${probe}.conf" || exit $?

    if [ -f /usr/data/printer_data/config/${probe}_calibrate.cfg ]; then
        rm /usr/data/printer_data/config/${probe}_calibrate.cfg
    fi
    $CONFIG_HELPER --remove-include "${probe}_calibrate.cfg" || exit $?

    [ -f /usr/data/printer_data/config/$probe-${model}.cfg ] && rm /usr/data/printer_data/config/$probe-${model}.cfg
    $CONFIG_HELPER --remove-include "$probe-${model}.cfg" || exit $?
}

function setup_bltouch() {
    grep -q "bltouch-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up bltouch/crtouch/3dtouch ..."

        cleanup_probe microprobe
        cleanup_probe btteddy
        cleanup_probe cartotouch
        cleanup_probe beacon

        # we merge bltouch.cfg into printer.cfg so that z_offset can be set
        if [ -f /usr/data/printer_data/config/bltouch.cfg ]; then
          rm /usr/data/printer_data/config/bltouch.cfg
        fi
        $CONFIG_HELPER --remove-include "bltouch.cfg" || exit $?
        $CONFIG_HELPER --overrides "/usr/data/pellcorp/k1/bltouch.cfg" || exit $?

        cp /usr/data/pellcorp/k1/bltouch_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "bltouch_macro.cfg" || exit $?

        cp /usr/data/pellcorp/k1/bltouch-${model}.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "bltouch-${model}.cfg" || exit $?

        # because the model sits out the back we do need to set position max back
        position_max=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max")
        position_max=$((position_max-17))
        $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "$position_max" || exit $?

        echo "bltouch-probe" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function setup_microprobe() {
    grep -q "microprobe-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up microprobe ..."

        cleanup_probe bltouch
        cleanup_probe btteddy
        cleanup_probe cartotouch
        cleanup_probe beacon

        # we merge microprobe.cfg into printer.cfg so that z_offset can be set
        if [ -f /usr/data/printer_data/config/microprobe.cfg ]; then
          rm /usr/data/printer_data/config/microprobe.cfg
        fi
        $CONFIG_HELPER --remove-include "microprobe.cfg" || exit $?
        $CONFIG_HELPER --overrides "/usr/data/pellcorp/k1/microprobe.cfg" || exit $?

        cp /usr/data/pellcorp/k1/microprobe_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "microprobe_macro.cfg" || exit $?

        cp /usr/data/pellcorp/k1/microprobe-${model}.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "microprobe-${model}.cfg" || exit $?

        echo "microprobe-probe" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function set_serial_cartotouch() {
    local SERIAL_ID=$(ls /dev/serial/by-id/usb-Cartographer* | head -1)
    if [ -n "$SERIAL_ID" ]; then
        local EXISTING_SERIAL_ID=$($CONFIG_HELPER --file cartotouch.cfg --get-section-entry "scanner" "serial")
        if [ "$EXISTING_SERIAL_ID" != "$SERIAL_ID" ]; then
            $CONFIG_HELPER --file cartotouch.cfg --replace-section-entry "scanner" "serial" "$SERIAL_ID" || exit $?
            return 1
        else
            echo "Serial value is unchanged"
            return 0
        fi
    else
        echo "WARNING: There does not seem to be a cartographer attached - skipping auto configuration"
        return 0
    fi
}

function setup_cartotouch() {
    grep -q "cartotouch-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up carto touch ..."

        cleanup_probe bltouch
        cleanup_probe microprobe
        cleanup_probe btteddy
        cleanup_probe beacon

        cp /usr/data/pellcorp/k1/cartographer.conf /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "cartographer.conf" || exit $?

        cp /usr/data/pellcorp/k1/cartotouch_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartotouch_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp /usr/data/pellcorp/k1/cartotouch.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartotouch.cfg" || exit $?

        set_serial_cartotouch

        # a slight change to the way cartotouch is configured
        $CONFIG_HELPER --remove-section "force_move" || exit $?

        # as we are referencing the included cartographer now we want to remove the included value
        # from any previous installation
        $CONFIG_HELPER --remove-section "scanner" || exit $?
        $CONFIG_HELPER --add-section "scanner" || exit $?

        scanner_touch_z_offset=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry scanner scanner_touch_z_offset)
        if [ -n "$scanner_touch_z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "scanner" "# scanner_touch_z_offset" "0.05" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "scanner" "scanner_touch_z_offset" "0.05" || exit $?
        fi

        scanner_mode=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry scanner mode)
        if [ -n "$scanner_mode" ]; then
            $CONFIG_HELPER --replace-section-entry "scanner" "# mode" "touch" || exit $?
        else
            $CONFIG_HELPER --replace-section-entry "scanner" "mode" "touch" || exit $?
        fi

        cp /usr/data/pellcorp/k1/cartographer-${model}.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartographer-${model}.cfg" || exit $?

        # because the model sits out the back we do need to set position max back
        position_max=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max")
        position_max=$((position_max-16))
        $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "$position_max" || exit $?

        cp /usr/data/pellcorp/k1/cartographer_calibrate.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartographer_calibrate.cfg" || exit $?

        echo "cartotouch-probe" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function set_serial_beacon() {
    local SERIAL_ID=$(ls /dev/serial/by-id/usb-Beacon_Beacon* | head -1)
    if [ -n "$SERIAL_ID" ]; then
        local EXISTING_SERIAL_ID=$($CONFIG_HELPER --file beacon.cfg --get-section-entry "beacon" "serial")
        if [ "$EXISTING_SERIAL_ID" != "$SERIAL_ID" ]; then
            $CONFIG_HELPER --file beacon.cfg --replace-section-entry "beacon" "serial" "$SERIAL_ID" || exit $?
            return 1
        else
            echo "Serial value is unchanged"
            return 0
        fi
    else
        echo "WARNING: There does not seem to be a beacon attached - skipping auto configuration"
        return 0
    fi
}

function setup_beacon() {
    grep -q "beacon-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up beacon ..."

        cleanup_probe bltouch
        cleanup_probe microprobe
        cleanup_probe btteddy
        cleanup_probe cartotouch

        cp /usr/data/pellcorp/k1/beacon.conf /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "beacon.conf" || exit $?

        cp /usr/data/pellcorp/k1/beacon_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "beacon_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp /usr/data/pellcorp/k1/beacon.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "beacon.cfg" || exit $?

        # for beacon can't use homing override
        $CONFIG_HELPER --file sensorless.cfg --remove-section "homing_override"
        # beacon homes z separately
        $CONFIG_HELPER --file sensorless.cfg --remove-section "gcode_macro _HOME_Z"
        $CONFIG_HELPER --file sensorless.cfg --remove-section-entry "gcode_macro _SENSORLESS_PARAMS" "variable_safe_z"
        $CONFIG_HELPER --file sensorless.cfg --remove-section-entry "gcode_macro _SENSORLESS_PARAMS" "variable_force_move"
        $CONFIG_HELPER --file sensorless.cfg --remove-section-entry "gcode_macro _SENSORLESS_PARAMS" "variable_move_centre"

        y_position_max=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max")
        # make sure to remove any floating point portion
        y_position_max=$(printf '%0.f' "$y_position_max")
        x_position_max=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_max")
        # make sure to remove any floating point portion
        x_position_max=$(printf '%0.f' "$x_position_max")

        y_position_mid=$((y_position_max/2))
        x_position_mid=$((x_position_max/2))

        $CONFIG_HELPER --file beacon.cfg --replace-section-entry "beacon" "home_xy_position" "$x_position_mid,$y_position_mid" || exit $?

        set_serial_beacon

        # as we are referencing the included cartographer now we want to remove the included value
        # from any previous installation
        $CONFIG_HELPER --remove-section "beacon" || exit $?
        $CONFIG_HELPER --add-section "beacon" || exit $?

        beacon_cal_nozzle_z=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry beacon cal_nozzle_z)
        if [ -n "$beacon_cal_nozzle_z" ]; then
          $CONFIG_HELPER --replace-section-entry "beacon" "# cal_nozzle_z" "0.1" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "beacon" "cal_nozzle_z" "0.1" || exit $?
        fi

        cp /usr/data/pellcorp/k1/beacon-${model}.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "beacon-${model}.cfg" || exit $?

        # 25mm for safety in case someone is using a RevD or low profile, lots of space to reclaim
        # if you are using the side mount
        position_max=$((position_max-25))
        $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "$position_max" || exit $?

        echo "beacon-probe" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function set_serial_btteddy() {
    local SERIAL_ID=$(ls /dev/serial/by-id/usb-Klipper_rp2040* | head -1)
    if [ -n "$SERIAL_ID" ]; then
        local EXISTING_SERIAL_ID=$($CONFIG_HELPER --file btteddy.cfg --get-section-entry "mcu eddy" "serial")
        if [ "$EXISTING_SERIAL_ID" != "$SERIAL_ID" ]; then
            $CONFIG_HELPER --file btteddy.cfg --replace-section-entry "mcu eddy" "serial" "$SERIAL_ID" || exit $?
            return 1
        else
            echo "Serial value is unchanged"
            return 0
        fi
    else
        echo "WARNING: There does not seem to be a btt eddy attached - skipping auto configuration"
        return 0
    fi
}

function setup_btteddy() {
    grep -q "btteddy-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up btteddy ..."

        cleanup_probe bltouch
        cleanup_probe microprobe
        cleanup_probe cartotouch
        cleanup_probe beacon

        cp /usr/data/pellcorp/k1/btteddy.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy.cfg" || exit $?

        set_serial_btteddy

        cp /usr/data/pellcorp/k1/btteddy_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy_macro.cfg" || exit $?

        # K1 SE has no chamber fan
        if [ "$MODEL" = "K1 SE" ]; then
            sed -i '/SET_FAN_SPEED FAN=chamber.*/d' /usr/data/printer_data/config/btteddy_macro.cfg
        fi

        $CONFIG_HELPER --remove-section "probe_eddy_current btt_eddy" || exit $?
        $CONFIG_HELPER --add-section "probe_eddy_current btt_eddy" || exit $?

        cp /usr/data/pellcorp/k1/btteddy-${model}.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy-${model}.cfg" || exit $?

        # because the model sits out the back we do need to set position max back
        position_max=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max")
        position_max=$((position_max-16))
        $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "$position_max" || exit $?

        cp /usr/data/pellcorp/k1/btteddy_calibrate.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy_calibrate.cfg" || exit $?

        echo "btteddy-probe" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function install_entware() {
    local mode=$1
    if ! grep -q "entware" /usr/data/pellcorp.done; then
        echo
        /usr/data/pellcorp/k1/entware-install.sh "$mode" || exit $?

        echo "entware" >> /usr/data/pellcorp.done
        sync
    fi
}

function apply_overrides() {
    return_status=0
    grep -q "overrides" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        /usr/data/pellcorp/k1/apply-overrides.sh
        return_status=$?
        echo "overrides" >> /usr/data/pellcorp.done
        sync
    fi
    return $return_status
}

# this stuff we do not want to have a log file for
if [ "$1" = "--update-repo" ] || [ "$1" = "--update-branch" ]; then
    update_repo /usr/data/pellcorp
    exit $?
elif [ "$1" = "--branch" ] && [ -n "$2" ]; then # convenience for testing new features
    update_repo /usr/data/pellcorp $2 || exit $?
    exit $?
elif [ "$1" = "--cartographer-branch" ]; then
    shift
    if [ -d /usr/data/cartographer-klipper ]; then
        branch=master
        channel=stable
        if [ "$1" = "stable" ]; then
            branch=master
        elif [ "$1" = "beta" ]; then
            branch=beta
            channel=dev
        else
            branch=$1
            channel=dev
        fi
        update_repo /usr/data/cartographer-klipper $branch || exit $?
        update_klipper || exit $?
        if [ -f /usr/data/printer_data/config/cartographer.conf ]; then
            $CONFIG_HELPER --file cartographer.conf --replace-section-entry 'update_manager cartographer' channel $channel || exit $?
            $CONFIG_HELPER --file cartographer.conf --replace-section-entry 'update_manager cartographer' primary_branch $branch || exit $?
            restart_moonraker || exit $?
        fi
    else
        echo "Error cartographer-klipper repo does not exist"
        exit 1
    fi
    exit 0
elif [ "$1" = "--klipper-branch" ]; then # convenience for testing new features
    if [ -n "$2" ]; then
        update_repo /usr/data/klipper $2 || exit $?
        update_klipper || exit $?
        exit 0
    else
        echo "Error invalid branch specified"
        exit 1
    fi
elif [ "$1" = "--klipper-repo" ]; then # convenience for testing new features
    if [ -n "$2" ]; then
        klipper_repo=$2
        if [ "$klipper_repo" = "k1-carto-klipper" ]; then
            echo "ERROR: Switching to k1-carto-klipper is no longer supported"
            exit 1
        fi

        if [ -d /usr/data/klipper/.git ]; then
            cd /usr/data/klipper/
            remote_repo=$(git remote get-url origin | awk -F '/' '{print $NF}' | sed 's/.git//g')
            cd - > /dev/null
            if [ "$remote_repo" != "$klipper_repo" ]; then
                echo "INFO: Switching klipper from pellcorp/$remote_repo to pellcorp/${klipper_repo} ..."
                rm -rf /usr/data/klipper

                echo "$klipper_repo" > /usr/data/pellcorp.klipper
            fi
        fi

        if [ ! -d /usr/data/klipper ]; then
            git clone https://github.com/pellcorp/${klipper_repo}.git /usr/data/klipper || exit $?
            if [ -n "$3" ]; then
              cd /usr/data/klipper && git switch $3 && cd - > /dev/null
            fi
        else
            update_repo /usr/data/klipper $3 || exit $?
        fi

        update_klipper || exit $?
        exit 0
    else
        echo "Error invalid klipper repo specified"
        exit 1
    fi
fi

export TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE=/usr/data/printer_data/logs/installer-$TIMESTAMP.log

{
    # figure out what existing probe if any is being used
    probe=
    if [ -f /usr/data/printer_data/config/bltouch-k1.cfg ] || [ -f /usr/data/printer_data/config/bltouch-k1m.cfg ]; then
        probe=bltouch
    elif [ -f /usr/data/printer_data/config/cartotouch.cfg ]; then
        probe=cartotouch
    elif [ -f /usr/data/printer_data/config/beacon.cfg ]; then
        probe=beacon
    elif grep -q "\[scanner\]" /usr/data/printer_data/config/printer.cfg; then
        probe=cartotouch
    elif [ -f /usr/data/printer_data/config/microprobe-k1.cfg ] || [ -f /usr/data/printer_data/config/microprobe-k1m.cfg ]; then
        probe=microprobe
    elif [ -f /usr/data/printer_data/config/btteddy-k1.cfg ] || [ -f /usr/data/printer_data/config/btteddy-k1m.cfg ]; then
        probe=btteddy
    elif [ -f /usr/data/printer_data/config/cartographer-k1.cfg ] || [ -f /usr/data/printer_data/config/cartographer-k1m.cfg ]; then
        probe=cartographer
    fi

    client=cli
    mode=install
    skip_overrides=false
    mount=
    # parse arguments here

    while true; do
        if [ "$1" = "--fix-serial" ] || [ "$1" = "--install" ] || [ "$1" = "--update" ] || [ "$1" = "--reinstall" ] || [ "$1" = "--clean-install" ] || [ "$1" = "--clean-update" ] || [ "$1" = "--clean-reinstall" ]; then
            mode=$(echo $1 | sed 's/--//g')
            shift
            if [ "$mode" = "clean-install" ] || [ "$mode" = "clean-reinstall" ] || [ "$mode" = "clean-update" ]; then
                skip_overrides=true
                mode=$(echo $mode | sed 's/clean-//g')
            fi
        elif [ "$1" = "--mount" ]; then
            shift
            mount=$1
            if [ -z "$mount" ]; then
                mount=unknown
            fi
            shift
        elif [ "$1" = "--client" ]; then
            shift
            client=$1
            shift
        elif [ "$1" = "microprobe" ] || [ "$1" = "bltouch" ] || [ "$1" = "beacon" ] || [ "$1" = "cartographer" ] || [ "$1" = "cartotouch" ] || [ "$1" = "btteddy" ]; then
            if [ "$mode" = "fix-serial" ]; then
                echo "ERROR: Switching probes is not supported while trying to fix serial!"
                exit 1
            fi
            if [ -n "$probe" ] && [ "$1" != "$probe" ]; then
              echo "WARNING: About to switch from $probe to $1!"
            fi
            probe=$1
            shift
        elif [ -n "$1" ]; then # no more valid parameters
            break
        else # no more parameters
            break
        fi
    done

    if [ -z "$probe" ]; then
        echo "ERROR: You must specify a probe you want to configure"
        echo "One of: [microprobe, bltouch, cartotouch, btteddy, beacon]"
        exit 1
    fi

    echo "INFO: Mode is $mode"
    echo "INFO: Probe is $probe"

    if [ -n "$mount" ]; then
        /usr/data/pellcorp/k1/apply-mount-overrides.sh --verify $probe $mount
        if [ $? -eq 0 ]; then
            echo "INFO: Mount is $mount"
        else
            exit 1
        fi
    fi
    echo

    if [ "$probe" = "cartographer" ]; then
      echo "ERROR: Cartographer for 4.0.0 firmware is no longer supported!"
      exit 1
    fi

    if [ "$mode" = "fix-serial" ]; then
        if [ -f /usr/data/pellcorp.done ]; then
            if [ "$probe" = "cartotouch" ]; then
                set_serial_cartotouch
                set_serial=$?
            elif [ "$probe" = "beacon" ]; then
                set_serial_beacon
                set_serial=$?
            elif [ "$probe" = "btteddy" ]; then
                set_serial_btteddy
                set_serial=$?
            else
                echo "ERROR: Fix serial not supported for $probe"
                exit 1
            fi

            if [ $set_serial -ne 0 ]; then
                if [ "$client" = "cli" ]; then
                    echo
                    echo "INFO: Restarting Klipper ..."
                    /etc/init.d/S55klipper_service restart
                else
                    echo "WARNING: Klipper restart required"
                fi
            fi
            exit 0
        else
            echo "ERROR: No installation found"
            exit 1
        fi
    fi

    # to avoid cluttering the printer_data/config directory lets move stuff
    mkdir -p /usr/data/printer_data/config/backups/
    mv /usr/data/printer_data/config/*.bkp /usr/data/printer_data/config/backups/ 2> /dev/null

    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    cd /usr/data/printer_data/config/

    CFG_ARG='*.cfg'
    CONF_ARG=''
    ls *.conf > /dev/null 2>&1
    # straight from a factory reset, there will be no conf files
    if [ $? -eq 0 ]; then
        CONF_ARG='*.conf'
    fi
    tar -zcf /usr/data/printer_data/config/backups/backup-${TIMESTAMP}.tar.gz $CFG_ARG $CONF_ARG
    cd - > /dev/null
    sync

    mkdir -p /usr/data/pellcorp-backups

    # the pellcorp-backups do not need .pellcorp extension, so this is to fix backwards compatible
    if [ -f /usr/data/pellcorp-backups/printer.pellcorp.cfg ]; then
        mv /usr/data/pellcorp-backups/printer.pellcorp.cfg /usr/data/pellcorp-backups/printer.cfg
    fi

    # so if the installer has never been run we should grab a backup of the printer.cfg
    if [ ! -f /usr/data/pellcorp.done ] && [ ! -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
        # just to make sure we don't accidentally copy printer.cfg to backup if the backup directory
        # is deleted, add a stamp to config files to we can know for sure.
        if ! grep -q "# Modified by Simple AF " /usr/data/printer_data/config/printer.cfg; then
            cp /usr/data/printer_data/config/printer.cfg /usr/data/pellcorp-backups/printer.factory.cfg
        else
          echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
          echo "WARNING: No pristine factory printer.cfg available - config overrides are disabled!"
          echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
        fi
    fi

    if [ "$skip_overrides" = "true" ]; then
        echo "INFO: Configuration overrides will not be saved or applied"
    fi

    # we want to disable creality services at the very beginning otherwise shit gets weird
    # if the crazy creality S55klipper_service is still copying files
    disable_creality_services

    install_config_updater

    # completely remove all iterations of zero SimpleAddon
    for dir in addons SimpleAddon; do
      if [ -d /usr/data/printer_data/config/$dir ]; then
        rm -rf /usr/data/printer_data/config/$dir
      fi
    done
    for file in save-zoffset.cfg eddycalibrate.cfg quickstart.cfg cartographer_calibrate.cfg btteddy_calibrate.cfg; do
      $CONFIG_HELPER --remove-include "SimpleAddon/$file"
      sync
    done
    $CONFIG_HELPER --remove-include "addons/*.cfg"
    sync

    if [ "$mode" = "reinstall" ] || [ "$mode" = "update" ]; then
        if [ "$skip_overrides" != "true" ]; then
            if [ -f /usr/data/pellcorp-backups/printer.cfg ]; then
                /usr/data/pellcorp/k1/config-overrides.sh
            elif [ -f /usr/data/pellcorp.done ]; then # for a factory reset this warning is superfluous
              echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
              echo "WARNING: No /usr/data/pellcorp-backups/printer.cfg - config overrides won't be generated!"
              echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
            fi
        fi

        if [ -f /usr/data/pellcorp.done ]; then
          rm /usr/data/pellcorp.done
        fi

        # if we took a post factory reset backup for a reinstall restore it now
        if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
            # lets just repair existing printer.factory.cfg if someone failed to factory reset, we will get them next time
            # but config overrides should generally work even if its not truly a factory config file
            if grep -q "#*# <---------------------- SAVE_CONFIG ---------------------->" /usr/data/pellcorp-backups/printer.factory.cfg; then
                sed -i '/^#*#/d' /usr/data/pellcorp-backups/printer.factory.cfg
            fi

            cp /usr/data/pellcorp-backups/printer.factory.cfg /usr/data/printer_data/config/printer.cfg
            DATE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
            sed -i "1s/^/# Modified by Simple AF ${DATE_TIME}\n/" /usr/data/printer_data/config/printer.cfg
        elif [ "$mode" = "update" ]; then
            echo "ERROR: Update mode is not available as pristine factory printer.cfg is missing"
            exit 1
        fi
    fi
    sync

    # add a service to take care of updating various config files if ip address changes
    cp /usr/data/pellcorp/k1/services/S96ipaddress /etc/init.d/

    if [ -L /usr/data/printer_data/logs/messages ]; then
      rm /usr/data/printer_data/logs/messages
    fi
    ln -sf /var/log/messages /usr/data/printer_data/logs/messages.log

    # lets make sure we are not stranded in some repo dir
    cd /root

    touch /usr/data/pellcorp.done
    sync

    install_entware $mode
    install_webcam $mode
    install_boot_display

    install_moonraker $mode
    install_moonraker=$?

    install_nginx $mode
    install_nginx=$?

    install_fluidd $mode
    install_fluidd=$?

    install_mainsail $mode
    install_mainsail=$?

    # KAMP is in the moonraker.conf file so it must be installed before moonraker is first started
    install_kamp $mode
    install_kamp=$?

    install_klipper $mode $probe
    install_klipper=$?

    install_cartographer_klipper=0
    install_beacon_klipper=0
    if [ "$probe" = "cartographer" ] || [ "$probe" = "cartotouch" ]; then
      install_cartographer_klipper $mode
      install_cartographer_klipper=$?
    elif [ "$probe" = "beacon" ]; then
      install_beacon_klipper $mode
      install_beacon_klipper=$?
    fi

    install_guppyscreen $mode
    install_guppyscreen=$?

    setup_probe
    setup_probe=$?

    if [ "$probe" = "cartotouch" ]; then
        setup_cartotouch
        setup_probe_specific=$?
    elif [ "$probe" = "bltouch" ]; then
        setup_bltouch
        setup_probe_specific=$?
    elif [ "$probe" = "btteddy" ]; then
        setup_btteddy
        setup_probe_specific=$?
    elif [ "$probe" = "microprobe" ]; then
        setup_microprobe
        setup_probe_specific=$?
    elif [ "$probe" = "beacon" ]; then
        setup_beacon
        setup_probe_specific=$?
    else
        echo "ERROR: Probe $probe not supported"
        exit 1
    fi

    apply_mount_overrides=0
    if [ -n "$mount" ]; then
        /usr/data/pellcorp/k1/apply-mount-overrides.sh $probe $mount
        apply_mount_overrides=$?
    fi

    apply_overrides=0
    # there will be no support for generating pellcorp-overrides unless you have done a factory reset
    if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
        probe_model=${probe}

        if [ "$probe" = "cartotouch" ]; then
            probe_model=cartographer
        fi

        # we want a copy of the file before config overrides are re-applied so we can correctly generate diffs
        # against different generations of the original file
        for file in printer.cfg start_end.cfg fan_control.cfg useful_macros.cfg $probe_model.conf moonraker.conf webcam.conf sensorless.cfg ${probe}_macro.cfg ${probe}.cfg ${probe_model}-${model}.cfg; do
            if [ -f /usr/data/printer_data/config/$file ]; then
                cp /usr/data/printer_data/config/$file /usr/data/pellcorp-backups/$file
            fi
        done

        if [ -f /usr/data/guppyscreen/guppyscreen.json ]; then
          cp /usr/data/guppyscreen/guppyscreen.json /usr/data/pellcorp-backups/
        fi

        if [ "$skip_overrides" != "true" ]; then
            apply_overrides
            apply_overrides=$?
        fi
    fi

    /usr/data/pellcorp/k1/update-ip-address.sh
    update_ip_address=$?

    if [ $apply_overrides -ne 0 ] || [ $install_moonraker -ne 0 ] || [ $install_cartographer_klipper -ne 0 ] || [ $install_beacon_klipper -ne 0 ] || [ $update_ip_address -ne 0 ]; then
        if [ "$client" = "cli" ]; then
            restart_moonraker
        else
            echo "WARNING: Moonraker restart required"
        fi
    fi

    if [ $install_moonraker -ne 0 ] || [ $install_nginx -ne 0 ] || [ $install_fluidd -ne 0 ] || [ $install_mainsail -ne 0 ]; then
        if [ "$client" = "cli" ]; then
            echo
            echo "INFO: Restarting Nginx ..."
            /etc/init.d/S50nginx_service restart
        else
            echo "WARNING: NGINX restart required"
        fi
    fi

    if [ $apply_overrides -ne 0 ] || [ $apply_mount_overrides -ne 0 ] || [ $install_cartographer_klipper -ne 0 ] || [ $install_beacon_klipper -ne 0 ] || [ $install_kamp -ne 0 ] || [ $install_klipper -ne 0 ] || [ $setup_probe -ne 0 ] || [ $setup_probe_specific -ne 0 ]; then
        if [ "$client" = "cli" ]; then
            echo
            echo "INFO: Restarting Klipper ..."
            /etc/init.d/S55klipper_service restart
        else
            echo "WARNING: Klipper restart required"
        fi
    fi

    if [ $apply_overrides -ne 0 ] || [ $install_guppyscreen -ne 0 ]; then
        if [ "$client" = "cli" ]; then
            echo
            echo "INFO: Restarting Guppyscreen ..."
            /etc/init.d/S99guppyscreen restart
        else
            echo "WARNING: Guppyscreen restart required"
        fi
    fi

    echo
    /usr/data/pellcorp/k1/tools/check-firmware.sh

    exit 0
} 2>&1 | tee -a $LOG_FILE
