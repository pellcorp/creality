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

if [ "$MODEL" != "CR-K1" ] && [ "$MODEL" != "K1C" ] && [ "$MODEL" != "CR-K1 Max" ]; then
    echo "This script is only supported for the K1, K1C and CR-K1 Max!"
    exit 1
fi

# now map it to the probe file name suffix
if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
  model=k1
elif [ "$MODEL" = "CR-K1 Max" ]; then
  model=k1m
fi

if [ -d /usr/data/helper-script ] || [ -f /usr/data/fluidd.sh ] || [ -f /usr/data/mainsail.sh ]; then
    echo "The Guilouz helper and K1_Series_Annex scripts cannot be installed"
    exit 1
fi

# everything else in the script assumes its cloned to /usr/data/pellcorp
# so we must verify this or shit goes wrong
if [ "$(dirname $(readlink -f $0))" != "/usr/data/pellcorp/k1" ]; then
  >&2 echo "ERROR: This git repo must be cloned to /usr/data/pellcorp"
  exit 1
fi

update_repo() {
    local repo_dir=$1
    
    if [ -d "${repo_dir}/.git" ]; then
        cd $repo_dir
        branch_ref=$(git rev-parse --abbrev-ref HEAD)
        if [ -n "$branch_ref" ]; then
            git fetch
            git reset --hard origin/$branch_ref
            sync
        else
            echo "Failed to detect current branch"
            return 1
        fi
    else
        echo "Invalid $repo_dir specified"
        return 1
    fi
    return 0
}

# special mode to update the repo only
if [ "$1" = "--update-repo" ] || [ "$1" = "--update-branch" ]; then
    update_repo /usr/data/pellcorp
    exit $?
elif [ "$1" = "--branch" ] && [ -n "$2" ]; then # convenience for testing new features
    update_repo /usr/data/pellcorp || exit $?
    cd /usr/data/pellcorp && git switch $2 && cd - > /dev/null
    update_repo /usr/data/pellcorp
    exit $?
elif [ "$1" = "--klipper-branch" ] && [ -n "$2" ]; then # convenience for testing new features
    update_repo /usr/data/klipper || exit $?
    cd /usr/data/klipper && git switch $2 && cd - > /dev/null
    update_repo /usr/data/klipper

    /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?
    exit $?
elif [ "$1" = "--klipper-repo" ] && [ -n "$2" ]; then # convenience for testing new features
    klipper_repo=$2
    if [ -d /usr/data/klipper/.git ]; then
        cd /usr/data/klipper/
        remote_repo=$(git remote get-url origin | awk -F '/' '{print $NF}' | sed 's/.git//g')
        cd - > /dev/null
        if [ "$remote_repo" != "$klipper_repo" ]; then
            echo "Switching klipper from pellcorp/$remote_repo to pellcorp/${klipper_repo} ..."
            rm -rf /usr/data/klipper

            echo "$klipper_repo" > /usr/data/pellcorp.klipper
        fi
    fi

    if [ ! -d /usr/data/klipper ]; then
        git clone https://github.com/pellcorp/${klipper_repo}.git /usr/data/klipper || exit $?
    else
        update_repo /usr/data/klipper || exit $?
    fi

    if [ -n "$3" ]; then
        cd /usr/data/klipper && git switch $3 && cd - > /dev/null
        update_repo /usr/data/klipper || exit $?
    fi
    if [ -d /usr/data/cartographer-klipper ]; then
        /usr/data/cartographer-klipper/install.sh || exit $?
        sync
    fi

    /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

    /usr/data/pellcorp/k1/check-firmware.sh --status
    if [ $? -eq 0 ]; then
        /etc/init.d/S55klipper_service restart
    fi
    exit $?
fi

# kill pip cache to free up overlayfs
rm -rf /root/.cache

cp /usr/data/pellcorp/k1/services/S58factoryreset /etc/init.d || exit $?
cp /usr/data/pellcorp/k1/services/S50dropbear /etc/init.d/ || exit $?
sync

# for k1 the installed curl does not do ssl, so we replace it first
# and we can then make use of it going forward
cp /usr/data/pellcorp/k1/tools/curl /usr/bin/curl

CONFIG_HELPER="/usr/data/pellcorp/k1/config-helper.py"

install_config_updater() {
    python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
    if [ $? -ne 0 ]; then
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
}

disable_creality_services() {
    if [ -f /etc/init.d/S99start_app ]; then
        echo ""
        echo "INFO: Disabling some creality services ..."

        if [ -f /etc/init.d/S99start_app ]; then
            echo "INFO: : If you reboot the printer before installing guppyscreen, the screen will be blank - this is to be expected!"
            /etc/init.d/S99start_app stop
            rm /etc/init.d/S99start_app
        fi

        if [ -f /etc/init.d/S70cx_ai_middleware ]; then
            /etc/init.d/S70cx_ai_middleware stop
            rm /etc/init.d/S70cx_ai_middleware
        fi
        if [ -f /etc/init.d/S97webrtc ]; then
            /etc/init.d/S97webrtc stop
            rm /etc/init.d/S97webrtc
        fi
        if [ -f /etc/init.d/S99mdns ]; then
            /etc/init.d/S99mdns stop
            rm /etc/init.d/S99mdns
        fi
        if [ -f /etc/init.d/S12boot_display ]; then
            rm /etc/init.d/S12boot_display
        fi
        if [ -f /etc/init.d/S96wipe_data ]; then
            rm /etc/init.d/S96wipe_data
        fi
        sync

        # the log main process takes up so much memory a lot of it swapped, killing this process might make the
        # installer go a little more quickly as there is no swapping going on
        log_main_pid=$(ps -ef | grep log_main | grep -v "grep" | awk '{print $1}')
        if [ -n "$log_main_pid" ]; then
            kill -9 $log_main_pid
        fi
    fi
}

install_webcam() {
    local mode=$1
    
    grep -q "webcam" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] || [ ! -f /opt/bin/mjpg_streamer ]; then
            echo ""
            echo "INFO: Installing mjpg streamer ..."
            /opt/bin/opkg install mjpg-streamer mjpg-streamer-input-http mjpg-streamer-input-uvc mjpg-streamer-output-http mjpg-streamer-www || exit $?
        fi

        echo "INFO: Updating webcam config ..."
        # we do not want to start the entware version of the service ever
        if [ -f /opt/etc/init.d/S96mjpg-streamer ]; then
            rm /opt/etc/init.d/S96mjpg-streamer
        fi
        # kill the existing creality services so that we can use the app right away without a restart
        pidof cam_app &>/dev/null && killall -TERM cam_app
        pidof mjpg_streamer &>/dev/null && killall -TERM mjpg_streamer

        if [ -f /etc/init.d/S50webcam ]; then
            /etc/init.d/S50webcam stop
        fi

        # auto_uvc.sh is responsible for starting the web cam_app
        [ -f /usr/bin/auto_uvc.sh ] && rm /usr/bin/auto_uvc.sh
        cp /usr/data/pellcorp/k1/files/auto_uvc.sh /usr/bin/
        chmod 777 /usr/bin/auto_uvc.sh

        cp /usr/data/pellcorp/k1/services/S50webcam /etc/init.d/
        /etc/init.d/S50webcam start

        cp /usr/data/pellcorp/k1/webcam.conf /usr/data/printer_data/config/ || exit $?

        # I don't know what IP this gets for K1 Max, but its only updating commented out config at the moment
        # so its not too much of an issue
        IP_ADDRESS=$(ip a | grep "inet" | grep -v "host lo" | awk '{ print $2 }' | awk -F '/' '{print $1}' | tail -1)
        if [ -n "$IP_ADDRESS" ]; then
            sed -i "s/xxx.xxx.xxx.xxx/$IP_ADDRESS/g" /usr/data/printer_data/config/webcam.conf
        fi

        echo "webcam" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

install_moonraker() {
    local mode=$1

    grep -q "moonraker" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        
        if [ "$mode" != "update" ] && [ -d /usr/data/moonraker ]; then
            if [ -f /etc/init.d/S56moonraker_service ]; then
                /etc/init.d/S56moonraker_service stop
            fi
            if [ -d /usr/data/printer_data/database/ ]; then
                [ -f /usr/data/moonraker-database.tar.gz ] && rm /usr/data/moonraker-database.tar.gz

                echo ""
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

            echo ""
            git clone https://github.com/Arksine/moonraker /usr/data/moonraker || exit $?

            if [ -f /usr/data/moonraker-database.tar.gz ]; then
                echo ""
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

install_nginx() {
    local mode=$1

    grep -q "nginx" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/nginx ]; then
            if [ -f /etc/init.d/S50nginx_service ]; then
                /etc/init.d/S50nginx_service stop
            fi
            rm -rf /usr/data/nginx
        fi

        if [ ! -d /usr/data/nginx ]; then
            echo ""
            echo "INFO: Installing nginx ..."

            tar -zxf /usr/data/pellcorp/k1/nginx.tar.gz -C /usr/data/ || exit $?
        fi

        echo "INFO: Updating nginx config ..."
        cp /usr/data/pellcorp/k1/nginx.conf /usr/data/nginx/nginx/ || exit $?
        mkdir -p /usr/data/nginx/nginx/sites/
        cp /usr/data/pellcorp/k1/nginx/fluidd /usr/data/nginx/nginx/sites/ || exit $?
        cp /usr/data/pellcorp/k1/nginx/mainsail /usr/data/nginx/nginx/sites/ || exit $?

        cp /usr/data/pellcorp/k1/services/S50nginx_service /etc/init.d/ || exit $?

        echo "nginx" >> /usr/data/pellcorp.done
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

install_fluidd() {
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
            echo ""
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

        $CONFIG_HELPER --add-include "fluidd.cfg" || exit $?

        echo "fluidd" >> /usr/data/pellcorp.done
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

install_mainsail() {
    local mode=$1

    grep -q "mainsail" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/mainsail ]; then
            rm -rf /usr/data/mainsail
        fi

        if [ ! -d /usr/data/mainsail ]; then
            echo ""
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

install_kamp() {
    local mode=$1

    grep -q "KAMP" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/KAMP ]; then
            rm -rf /usr/data/KAMP
        fi
        
        if [ ! -d /usr/data/KAMP/.git ]; then
            echo ""
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

        cp /usr/data/printer_data/config/KAMP_Settings.cfg /usr/data/pellcorp-backups/

        echo "KAMP" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

install_klipper() {
    local mode=$1
    local probe=$2

    grep -q "klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""

        klipper_repo=klipper
        # pellcorp/k1-carto-klipper is a version of klipper that is the same as k1-klipper/klipper k1_carto branch
        if [ "$probe" = "cartographer" ]; then
            klipper_repo=k1-carto-klipper
        fi
        if [ "$mode" != "update" ] && [ -d /usr/data/klipper ]; then
            if [ -f /etc/init.d/S55klipper_service ]; then
                /etc/init.d/S55klipper_service stop
            fi
            rm -rf /usr/data/klipper

            # a reinstall should reset the choice of what klipper to run
            if [ -f /usr/data/pellcorp.klipper ]; then
              rm /usr/data/pellcorp.klipper
            fi
        fi

        # switch to required klipper version except where there is a flag file indicating we explicitly
        # decided to use a particular version of klipper
        if [ -d /usr/data/klipper/.git ] && [ ! -f /usr/data/pellcorp.klipper ]; then
            cd /usr/data/klipper/
            remote_repo=$(git remote get-url origin | awk -F '/' '{print $NF}' | sed 's/.git//g')
            cd - > /dev/null
            if [ "$remote_repo" != "$klipper_repo" ]; then
                echo "INFO: Forcing Klipper repo to be switched to pellcorp/${klipper_repo}"
                rm -rf /usr/data/klipper/
            fi
        fi

        if [ -f /etc/init.d/S57klipper_mcu ]; then
            /etc/init.d/S55klipper_service stop
            /etc/init.d/S57klipper_mcu stop
            rm /etc/init.d/S57klipper_mcu
            /etc/init.d/S55klipper_service start > /dev/null
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

        cp /usr/data/pellcorp/k1/fan_control.cfg /usr/data/printer_data/config || exit $?
        $CONFIG_HELPER --add-include "fan_control.cfg" || exit $?

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
        $CONFIG_HELPER --remove-section "idle_timeout"

        echo "klipper" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

install_guppyscreen() {
    local mode=$1

    grep -q "guppyscreen" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then


        if [ "$mode" != "update" ] && [ -d /usr/data/guppyscreen ]; then
            if [ -f /etc/init.d/S99guppyscreen ]; then
              /etc/init.d/S99guppyscreen stop > /dev/null
              killall -q guppyscreen
            fi
            rm -rf /usr/data/guppyscreen
        fi

        if [ ! -d /usr/data/guppyscreen ]; then
            echo ""
            echo "INFO: Installing guppyscreen ..."

            curl -L "https://github.com/ballaswag/guppyscreen/releases/latest/download/guppyscreen.tar.gz" -o /usr/data/guppyscreen.tar.gz || exit $?
            tar xf /usr/data/guppyscreen.tar.gz -C /usr/data/ || exit $?
            rm /usr/data/guppyscreen.tar.gz 
        fi

        echo "INFO: Updating guppyscreen config ..."
        cp /usr/data/pellcorp/k1/services/S99guppyscreen /etc/init.d/ || exit $?
        cp /usr/data/pellcorp/k1/guppyconfig.json /usr/data/guppyscreen || exit $?

        if [ ! -d "/usr/lib/python3.8/site-packages/matplotlib-2.2.3-py3.8.egg-info" ]; then
            echo "WARNING: Not replacing mathplotlib ft2font module. PSD graphs might not work!"
        else
            cp /usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so /usr/lib/python3.8/site-packages/matplotlib/ || exit $?
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

setup_probe() {
    grep -q "probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
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

install_cartographer_klipper() {
    local mode=$1

    grep -q "cartographer-klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/cartographer-klipper ]; then
            rm -rf /usr/data/cartographer-klipper
        fi

        if [ ! -d /usr/data/cartographer-klipper ]; then
            echo ""
            echo "INFO: Installing cartographer-klipper ..."
            git clone https://github.com/Cartographer3D/cartographer-klipper.git /usr/data/cartographer-klipper || exit $?
        fi

        echo "INFO: Running cartographer-klipper installer ..."
        bash /usr/data/cartographer-klipper/install.sh || exit $?
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        echo "cartographer-klipper" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

cleanup_probe() {
    local probe=$1

    if [ "$probe" = "cartographer" ] || [ "$probe" = "cartotouch" ]; then
        [ -f /usr/data/printer_data/config/${probe}_macro.cfg ] && rm /usr/data/printer_data/config/${probe}_macro.cfg
        $CONFIG_HELPER --remove-include "${probe}_macro.cfg" || exit $?

        $CONFIG_HELPER --remove-section-entry "stepper_z" "homing_retract_dist" || exit $?
        $CONFIG_HELPER --file moonraker.conf --remove-include "cartographer.conf" || exit $?
    fi

    [ -f /usr/data/printer_data/config/$probe.cfg ] && rm /usr/data/printer_data/config/$probe.cfg
    $CONFIG_HELPER --remove-include "$probe.cfg" || exit $?

    # we use the cartographer includes
    if [ "$probe" = "cartotouch" ]; then
        probe=cartographer
    fi

    [ -f /usr/data/printer_data/config/$probe-${model}.cfg ] && rm /usr/data/printer_data/config/$probe-${model}.cfg
    $CONFIG_HELPER --remove-include "$probe-${model}.cfg" || exit $?
}

setup_bltouch() {
    grep -q "bltouch-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "INFO: Setting up bltouch/crtouch/3dtouch ..."

        cleanup_probe cartographer
        cleanup_probe microprobe
        cleanup_probe btteddy
        cleanup_probe cartotouch

        if [ -f /usr/data/printer_data/config/bltouch.cfg ]; then
          rm /usr/data/printer_data/config/bltouch.cfg
        fi
        $CONFIG_HELPER --remove-include "bltouch.cfg" || exit $?
        $CONFIG_HELPER --overrides "/usr/data/pellcorp/k1/bltouch.cfg" || exit $?

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

setup_microprobe() {
    grep -q "microprobe-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "INFO: Setting up microprobe ..."
        
        cleanup_probe cartographer
        cleanup_probe bltouch
        cleanup_probe btteddy
        cleanup_probe cartotouch

        if [ -f /usr/data/printer_data/config/microprobe.cfg ]; then
          rm /usr/data/printer_data/config/microprobe.cfg
        fi
        $CONFIG_HELPER --remove-include "microprobe.cfg" || exit $?
        $CONFIG_HELPER --overrides "/usr/data/pellcorp/k1/microprobe.cfg" || exit $?

        cp /usr/data/pellcorp/k1/microprobe-${model}.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "microprobe-${model}.cfg" || exit $?

        echo "microprobe-probe" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

setup_cartographer() {
    grep -q "cartographer-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "INFO: Setting up cartographer ..."

        cleanup_probe bltouch
        cleanup_probe microprobe
        cleanup_probe btteddy
        cleanup_probe cartotouch

        cp /usr/data/pellcorp/k1/cartographer.conf /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "cartographer.conf" || exit $?

        cp /usr/data/pellcorp/k1/cartographer_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartographer_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp /usr/data/pellcorp/k1/cartographer.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartographer.cfg" || exit $?

        CARTO_SERIAL_ID=$(ls /dev/serial/by-id/usb-Cartographer* | head -1)
        if [ -n "$CARTO_SERIAL_ID" ]; then
            $CONFIG_HELPER --file cartographer.cfg --replace-section-entry "cartographer" "serial" "$CARTO_SERIAL_ID" || exit $?
        else
            echo "WARNING: There does not seem to be a cartographer attached - skipping auto configuration"
        fi

        cp /usr/data/pellcorp/k1/cartographer-${model}.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartographer-${model}.cfg" || exit $?

        # because the model sits out the back we do need to set position max back
        position_max=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max")
        position_max=$((position_max-16))
        $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "$position_max" || exit $?

        echo "cartographer-probe" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

setup_cartotouch() {
    grep -q "cartotouch-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "INFO: Setting up carto touch ..."

        cleanup_probe bltouch
        cleanup_probe microprobe
        cleanup_probe btteddy
        cleanup_probe cartographer

        cp /usr/data/pellcorp/k1/cartographer.conf /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "cartographer.conf" || exit $?

        cp /usr/data/pellcorp/k1/cartotouch_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartotouch_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp /usr/data/pellcorp/k1/cartotouch.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartotouch.cfg" || exit $?

        # a slight change to the way cartotouch is configured
        $CONFIG_HELPER --remove-section "force_move" || exit $?

        CARTO_SERIAL_ID=$(ls /dev/serial/by-id/usb-Cartographer* | head -1)
        if [ -n "$CARTO_SERIAL_ID" ]; then
            $CONFIG_HELPER --file cartotouch.cfg --replace-section-entry "scanner" "serial" "$CARTO_SERIAL_ID" || exit $?
        else
            echo "WARNING: There does not seem to be a cartographer attached - skipping auto configuration"
        fi

        # as we are referencing the included cartographer now we want to remove the included value
        # from any previous installation
        $CONFIG_HELPER --remove-section "scanner" || exit $?
        $CONFIG_HELPER --add-section "scanner" || exit $?

        if grep -q "#*# [scanner]" /usr/data/pellcorp-overrides/printer.cfg.save_config 2> /dev/null; then
          $CONFIG_HELPER --replace-section-entry "scanner" "#scanner_touch_z_offset" "0.05" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "scanner" "scanner_touch_z_offset" "0.05" || exit $?
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

setup_btteddy() {
    grep -q "btteddy-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "INFO: Setting up btteddy ..."

        cleanup_probe bltouch
        cleanup_probe microprobe
        cleanup_probe cartographer
        cleanup_probe cartotouch

        cp /usr/data/pellcorp/k1/btteddy.cfg /usr/data/printer_data/config/ || exit $?
        
        BTTEDDY_SERIAL_ID=$(ls /dev/serial/by-id/usb-Klipper_rp2040* | head -1)
        if [ -n "$BTTEDDY_SERIAL_ID" ]; then
            $CONFIG_HELPER --file btteddy.cfg --replace-section-entry "mcu eddy" "serial" "$BTTEDDY_SERIAL_ID" || exit $?
        else
            echo "WARNING: There does not seem to be a btt eddy attached - skipping auto configuration"
        fi
        $CONFIG_HELPER --add-include "btteddy.cfg" || exit $?
        cp /usr/data/pellcorp/k1/btteddy_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy_macro.cfg" || exit $?

        $CONFIG_HELPER --remove-section "probe_eddy_current btt_eddy" || exit $?
        $CONFIG_HELPER --add-section "probe_eddy_current btt_eddy" || exit $?

        # for an update the save config has not as yet been reapplied to printer.cfg so we need to check the overrides
        # according to https://klipper.discourse.group/t/eddy-current-sensor-homing-and-calibration-problems/16670/11 setting
        # a bigger default reg_drive_current should allow the BTT_EDDY_CALIBRATE_DRIVE_CURRENT to return a more accurate value
        if grep -q "#*# [probe_eddy_current btt_eddy]" /usr/data/pellcorp-overrides/printer.cfg.save_config 2> /dev/null; then
          $CONFIG_HELPER --replace-section-entry "probe_eddy_current btt_eddy" "#reg_drive_current" "31" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "probe_eddy_current btt_eddy" "reg_drive_current" "31" || exit $?
        fi

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

install_entware() {
    local mode=$1
    if ! grep -q "entware" /usr/data/pellcorp.done; then
        echo ""
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

# thanks to @Nestaa51 for the timeout changes to not wait forever for moonraker
restart_moonraker() {
    echo ""
    echo "INFO: Restarting Moonraker ..."
    /etc/init.d/S56moonraker_service restart

    timeout=60
    start_time=$(date +%s)

    # this is mostly for k1-qemu where Moonraker takes a while to start up
    echo "INFO: Waiting for Moonraker ..."
    while true; do
        KLIPPER_PATH=$(curl localhost:7125/printer/info 2> /dev/null | jq -r .result.klipper_path)
        # not sure why, but moonraker will start reporting the location of klipper as /usr/data/klipper
        # when using a soft link
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

# to avoid cluttering the printer_data/config directory lets move stuff
mkdir -p /usr/data/printer_data/config/backups/
mv /usr/data/printer_data/config/*.bkp /usr/data/printer_data/config/backups/ 2> /dev/null

mkdir -p /usr/data/pellcorp-backups
# so if the installer has never been run we should grab a backup of the printer.cfg
if [ ! -f /usr/data/pellcorp.done ] && [ ! -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
    cp /usr/data/printer_data/config/printer.cfg /usr/data/pellcorp-backups/printer.factory.cfg
fi

# figure out what existing probe if any is being used
probe=
if [ -f /usr/data/printer_data/config/bltouch-k1.cfg ] || [ -f /usr/data/printer_data/config/bltouch-k1m.cfg ]; then
    probe=bltouch
elif [ -f /usr/data/printer_data/config/cartotouch.cfg ]; then
  probe=cartotouch
elif grep -q "\[scanner\]" /usr/data/printer_data/config/printer.cfg; then
    probe=cartotouch
elif [ -f /usr/data/printer_data/config/cartographer-k1.cfg ] || [ -f /usr/data/printer_data/config/cartographer-k1m.cfg ]; then
    probe=cartographer
elif [ -f /usr/data/printer_data/config/microprobe-k1.cfg ] || [ -f /usr/data/printer_data/config/microprobe-k1m.cfg ]; then
    probe=microprobe
elif [ -f /usr/data/printer_data/config/btteddy-k1.cfg ] || [ -f /usr/data/printer_data/config/btteddy-k1m.cfg ]; then
    probe=btteddy
fi

mode=install
skip_overrides=false
debug=false
# parse arguments here
while true; do
    if [ "$1" = "--install" ] || [ "$1" = "--update" ] || [ "$1" = "--reinstall" ] || [ "$1" = "--clean-install" ] || [ "$1" = "--clean-update" ] || [ "$1" = "--clean-reinstall" ]; then
        mode=$(echo $1 | sed 's/--//g')
        shift
        if [ "$mode" = "clean-install" ] || [ "$mode" = "clean-reinstall" ] || [ "$mode" = "clean-update" ]; then
            skip_overrides=true
            mode=$(echo $mode | sed 's/clean-//g')
        fi
    elif [ "$1" = "--debug" ]; then
        shift
        debug=true
    elif [ "$1" = "microprobe" ] || [ "$1" = "bltouch" ] || [ "$1" = "cartographer" ] || [ "$1" = "cartotouch" ] || [ "$1" = "btteddy" ]; then
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
    echo "One of: [microprobe, bltouch, cartographer, cartotouch, btteddy]"
    exit 1
fi

echo ""
echo "INFO: Mode is $mode"
echo "INFO: Probe is $probe"
echo ""

if [ "$skip_overrides" = "true" ]; then
    echo "INFO: Configuration overrides will not be saved or applied"
fi

# completely remove all iterations of zero SimpleAddon
for dir in addons SimpleAddon; do
  if [ -d /usr/data/printer_data/config/$dir ]; then
    rm -rf /usr/data/printer_data/config/$dir
  fi
done
for file in save-zoffset.cfg eddycalibrate.cfg quickstart.cfg cartographer_calibrate.cfg btteddy_calibrate.cfg; do
  $CONFIG_HELPER --remove-include "SimpleAddon/$file"
done
$CONFIG_HELPER --remove-include "addons/*.cfg"

# the pellcorp-backups do not need .pellcorp extension, so this is to fix backwards compatible
if [ -f /usr/data/pellcorp-backups/printer.pellcorp.cfg ]; then
    mv /usr/data/pellcorp-backups/printer.pellcorp.cfg /usr/data/pellcorp-backups/printer.cfg
fi

if [ "$mode" = "reinstall" ] || [ "$mode" = "update" ]; then
    if [ "$skip_overrides" != "true" ] && [ -f /usr/data/pellcorp-backups/printer.cfg ]; then
        /usr/data/pellcorp/k1/config-overrides.sh
    fi

    if [ -f /usr/data/pellcorp.done ]; then
      rm /usr/data/pellcorp.done
    fi

    # if we took a post factory reset backup for a reinstall restore it now
    if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
        cp /usr/data/pellcorp-backups/printer.factory.cfg /usr/data/printer_data/config/printer.cfg

        for file in printer.cfg moonraker.conf; do
            if [ -f /usr/data/pellcorp-backups/$file ]; then
                rm /usr/data/pellcorp-backups/$file
            fi
        done
    elif [ "$mode" = "update" ]; then
        echo "ERROR: Update mode is not available to users who have not done a factory reset since 27th of June 2024"
        exit 1
    fi
fi

# lets make sure we are not stranded in some repo dir
cd /root

touch /usr/data/pellcorp.done
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
cp /usr/data/printer_data/config/printer.cfg /usr/data/printer_data/config/backups/printer-${TIMESTAMP}.cfg

install_config_updater
install_entware $mode

install_webcam $mode

disable_creality_services

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
if [ "$probe" = "cartographer" ] || [ "$probe" = "cartotouch" ]; then
  install_cartographer_klipper $mode
  install_cartographer_klipper=$?
fi

# if moonraker was installed or updated
if [ $install_moonraker -ne 0 ] || [ $install_cartographer_klipper -ne 0 ]; then
    restart_moonraker
fi

if [ $install_klipper -ne 0 ] || [ $install_moonraker -ne 0 ] || [ $install_nginx -ne 0 ] || [ $install_fluidd -ne 0 ] || [ $install_mainsail -ne 0 ] || [ $install_cartographer_klipper -ne 0 ]; then
    echo ""
    echo "Restarting Nginx ..."
    /etc/init.d/S50nginx_service restart
fi

install_guppyscreen $mode
install_guppyscreen=$?

setup_probe
setup_probe=$?

# installing carto must come after installing klipper
if [ "$probe" = "cartographer" ]; then
    setup_cartographer
    setup_probe_specific=$?
elif [ "$probe" = "cartotouch" ]; then
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
else
    echo "Probe $probe not supported"
    exit 1
fi

# there will be no support for generating pellcorp-overrides unless you have done a factory reset
if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
    probe_model=${probe}
    if [ "$probe" = "cartotouch" ]; then
        probe_model=cartotouch
    fi

    # we want a copy of the file before config overrides are re-applied so we can correctly generate diffs
    # against different generations of the original file
    for file in printer.cfg start_end.cfg fan_control.cfg useful_macros.cfg moonraker.conf sensorless.cfg ${probe}_macro.cfg ${probe}.cfg ${probe_model}-${model}.cfg; do
        if [ -f /usr/data/printer_data/config/$file ]; then
            cp /usr/data/printer_data/config/$file /usr/data/pellcorp-backups/$file
        fi
    done
fi

apply_overrides=0
if [ "$skip_overrides" != "true" ]; then
    apply_overrides
    apply_overrides=$?

    # just restart moonraker in case any overrides were applied
    if [ $apply_overrides -ne 0 ]; then
        restart_moonraker
    fi
fi

if [ $apply_overrides -ne 0 ] || [ $install_cartographer_klipper -ne 0 ] || [ $install_kamp -ne 0 ] || [ $install_klipper -ne 0 ] || [ $install_guppyscreen -ne 0 ] || [ $setup_probe -ne 0 ] || [ $setup_probe_specific -ne 0 ]; then
    echo ""
    echo "Restarting Klipper ..."
    /etc/init.d/S55klipper_service restart
fi

if [ $install_guppyscreen -ne 0 ]; then
    echo ""
    echo "Restarting Guppyscreen ..."
    /etc/init.d/S99guppyscreen restart
fi

/usr/data/pellcorp/k1/check-firmware.sh
exit 0
