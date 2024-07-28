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
if [ "$1" = "--update-repo" ]; then
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
    exit $?
fi

# kill pip cache to free up overlayfs
rm -rf /root/.cache

cp /usr/data/pellcorp/k1/services/S58factoryreset /etc/init.d || exit $?
sync

cp /usr/data/pellcorp/k1/services/S50dropbear /etc/init.d/ || exit $?
sync

# for k1 the installed curl does not do ssl, so we replace it first
# and we can then make use of it going forward
cp /usr/data/pellcorp/k1/tools/curl /usr/bin/curl

CONFIG_HELPER="/usr/data/pellcorp/k1/config-helper.py"

install_config_updater() {
    python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
    if [ $? -ne 0 ]; then
        echo "Installing configupdater python package ..."
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
        echo "Disabling some creality services ..."

        if [ -f /etc/init.d/S99start_app ]; then
            echo "IMPORTANT: If you reboot the printer before installing guppyscreen, the screen will be blank - this is to be expected!"
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
    grep -q "webcam" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing mjpg streamer ..."
        /opt/bin/opkg install mjpg-streamer mjpg-streamer-input-http mjpg-streamer-input-uvc mjpg-streamer-output-http mjpg-streamer-www || exit $?

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
        # create an empty script to avoid udev getting upset
        touch /usr/bin/auto_uvc.sh
        chmod 777 /usr/bin/auto_uvc.sh

        cp /usr/data/pellcorp/k1/services/S50webcam /etc/init.d/
        /etc/init.d/S50webcam start
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
        if [ "$mode" = "update" ] && [ -d /usr/data/moonraker ]; then
            echo "Updating moonraker ..."

            update_repo /usr/data/moonraker || exit $?
        else
            echo "Installing moonraker ..."
        
            if [ -d /usr/data/moonraker ]; then
                if [ -f /etc/init.d/S56moonraker_service ]; then
                    /etc/init.d/S56moonraker_service stop
                fi
                if [ -d /usr/data/printer_data/database/ ]; then
                    [ -f  /usr/data/moonraker-database.tar.gz ] && rm /usr/data/moonraker-database.tar.gz

                    echo ""
                    echo "Backing up moonraker database ..."
                    cd /usr/data/printer_data/

                    tar -zcf /usr/data/moonraker-database.tar.gz database/
                    cd
                fi               
            fi
            [ -d /usr/data/moonraker ] && rm -rf /usr/data/moonraker
            [ -d /usr/data/moonraker-env ] && rm -rf /usr/data/moonraker-env

            echo ""
            git clone https://github.com/Arksine/moonraker /usr/data/moonraker || exit $?

            if [ -f /usr/data/moonraker-database.tar.gz ]; then
                echo ""
                echo "Restoring moonraker database ..."
                cd /usr/data/printer_data/
                tar -zxf /usr/data/moonraker-database.tar.gz
                rm /usr/data/moonraker-database.tar.gz
                cd
            fi
        fi

        # an existing bug where the moonraker secrets was not correctly copied
        if [ ! -f /usr/data/printer_data/moonraker.secrets ]; then
            cp /usr/data/pellcorp/k1/moonraker.secrets /usr/data/printer_data/
        fi

        echo "Upgrading ffmpeg for moonraker timelapse ..."
        /opt/bin/opkg install ffmpeg || exit $?

        ln -sf /usr/data/pellcorp/k1/tools/supervisorctl /usr/bin/ || exit $?
        tar -zxf /usr/data/pellcorp/k1/moonraker-env.tar.gz -C /usr/data/ || exit $?

        cp /usr/data/pellcorp/k1/services/S56moonraker_service /etc/init.d/ || exit $?
        cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/ || exit $?
        ln -sf /usr/data/pellcorp/k1/moonraker.asvc /usr/data/printer_data/ || exit $?
        cp /usr/data/pellcorp/k1/webcam.conf /usr/data/printer_data/config/ || exit $?

        if [ "$mode" = "update" ] && [ -d /usr/data/moonraker-timelapse ]; then
            update_repo /usr/data/moonraker-timelapse || exit $?
        else
            [ -d /usr/data/moonraker-timelapse ] && rm -rf /usr/data/moonraker-timelapse
            git clone https://github.com/mainsail-crew/moonraker-timelapse.git /usr/data/moonraker-timelapse/ || exit $?
        fi

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
    grep -q "nginx" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing nginx ..."

        # because the nginx tar ball is local, lets just redo the whole
        # thing, there should be no user configurable stuff here anyway
        if [ -d /usr/data/nginx ]; then
            if [ -f /etc/init.d/S50nginx_service ]; then
                /etc/init.d/S50nginx_service stop
            fi
            rm -rf /usr/data/nginx
        fi

        tar -zxf /usr/data/pellcorp/k1/nginx.tar.gz -C /usr/data/ || exit $?

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
        echo ""
        echo "Installing fluidd ..."

        [ -d /usr/data/fluidd ] && rm -rf /usr/data/fluidd

        mkdir -p /usr/data/fluidd || exit $?
        curl -L "https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip" -o /usr/data/fluidd.zip || exit $?
        unzip -qd /usr/data/fluidd /usr/data/fluidd.zip || exit $?
        rm /usr/data/fluidd.zip

        if [ "$mode" = "update" ] && [ -d /usr/data/fluidd-config ]; then
            update_repo /usr/data/fluidd-config || exit $?
        else
            [ -d /usr/data/fluidd-config ] && rm -rf /usr/data/fluidd-config
            git clone https://github.com/fluidd-core/fluidd-config.git /usr/data/fluidd-config || exit $?
        fi

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
    grep -q "mainsail" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing mainsail ..."

        [ -d /usr/data/mainsail ] && rm -rf /usr/data/mainsail

        mkdir -p /usr/data/mainsail || exit $?
        curl -L "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o /usr/data/mainsail.zip || exit $?
        unzip -qd /usr/data/mainsail /usr/data/mainsail.zip || exit $?
        rm /usr/data/mainsail.zip

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
        echo ""
        if [ "$mode" = "update" ] && [ -d /usr/data/KAMP ]; then
            echo "Updating KAMP ..."
            update_repo /usr/data/KAMP || exit $?
        else
            echo "Installing KAMP ..."
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

        ln -sf /usr/data/KAMP/Configuration/ /usr/data/printer_data/config/KAMP || exit $?

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

    grep -q "klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""

        if [ -f /etc/init.d/S57klipper_mcu ]; then
            /etc/init.d/S55klipper_service stop
            /etc/init.d/S57klipper_mcu stop
            rm /etc/init.d/S57klipper_mcu
            /etc/init.d/S55klipper_service start > /dev/null
        fi

        if [ "$mode" = "update" ] && [ -d /usr/data/klipper ]; then
            echo "Updating klipper ..."

            update_repo /usr/data/klipper || exit $?
        else
            echo "Installing klipper ..."

            if [ -d /usr/data/klipper ]; then
                if [ -f /etc/init.d/S55klipper_service ]; then
                    /etc/init.d/S55klipper_service stop
                fi
                rm -rf /usr/data/klipper
            fi

            if [ "$AF_GIT_CLONE" = "ssh" ]; then
                export GIT_SSH_IDENTITY=klipper
                export GIT_SSH=/usr/data/pellcorp/k1/ssh/git-ssh.sh
                git clone git@github.com:pellcorp/klipper.git /usr/data/klipper || exit $?
                # reset the origin url to make moonraker happy
                cd /usr/data/klipper && git remote set-url origin https://github.com/pellcorp/klipper.git && cd - > /dev/null
            else
                git clone https://github.com/pellcorp/klipper.git /usr/data/klipper || exit $?
            fi
            [ -d /usr/share/klipper ] && rm -rf /usr/share/klipper
        fi

        if [ -d /usr/data/cartographer-klipper ]; then
            rm -rf /usr/data/cartographer-klipper
        fi

        # we used to copy cartographer from cartographer-klipper repo now its integrated so remove exclude
        if grep -q "klippy/extras/cartographer.py" "/usr/data/klipper/.git/info/exclude"; then
            sed -i "/klippy\/extras\/cartographer.py$/d" "/usr/data/klipper/.git/info/exclude"
        fi

        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?
        ln -sf /usr/data/klipper /usr/share/ || exit $?
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

        echo "klipper" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

install_guppyscreen() {
    grep -q "guppyscreen" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing guppyscreen ..."

        if [ -d /usr/data/guppyscreen ]; then
            if [ -f /etc/init.d/S99guppyscreen ]; then
                /etc/init.d/S99guppyscreen stop &> /dev/null
            fi
            killall -q guppyscreen
            
            rm -rf /usr/data/guppyscreen
        fi
    
        curl -L "https://github.com/ballaswag/guppyscreen/releases/latest/download/guppyscreen.tar.gz" -o /usr/data/guppyscreen.tar.gz || exit $?
        tar xf /usr/data/guppyscreen.tar.gz  -C /usr/data/ || exit $?
        rm /usr/data/guppyscreen.tar.gz 
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
        echo "Setting up generic probe config ..."

        $CONFIG_HELPER --remove-section "bed_mesh" || exit $?
        $CONFIG_HELPER --remove-section-entry "stepper_z" "position_endstop" || exit $?
        $CONFIG_HELPER --replace-section-entry "stepper_z" "endstop_pin" "probe:z_virtual_endstop" || exit $?

        echo "probe" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

cleanup_probe() {
    local probe=$1

    if [ "$probe" = "cartographer" ]; then
        [ -f /usr/data/printer_data/config/cartographer_macro.cfg ] &&  rm /usr/data/printer_data/config/cartographer_macro.cfg
        $CONFIG_HELPER --remove-include "cartographer_macro.cfg" || exit $?

        $CONFIG_HELPER --remove-section-entry "stepper_z" "homing_retract_dist" || exit $?
    fi

    [ -f /usr/data/printer_data/config/$probe.cfg ] &&  rm /usr/data/printer_data/config/$probe.cfg
    $CONFIG_HELPER --remove-include "$probe.cfg" || exit $?

    if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
        [ -f /usr/data/printer_data/config/$probe-k1.cfg ] && rm /usr/data/printer_data/config/$probe-k1.cfg
        $CONFIG_HELPER --remove-include "$probe-k1.cfg" || exit $?
    elif [ "$MODEL" = "CR-K1 Max" ]; then
        [ -f /usr/data/printer_data/config/$probe-k1m.cfg ] && rm /usr/data/printer_data/config/$probe-k1m.cfg
        $CONFIG_HELPER --remove-include "$probe-k1m.cfg" || exit $?
    fi
}

setup_bltouch() {
    grep -q "bltouch-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "Setting up bltouch ..."

        cleanup_probe cartographer
        cleanup_probe microprobe
        cleanup_probe btteddy

        if [ -f /usr/data/printer_data/config/bltouch.cfg ]; then
          rm /usr/data/printer_data/config/bltouch.cfg
        fi
        $CONFIG_HELPER --remove-include "bltouch.cfg" || exit $?
        $CONFIG_HELPER --overrides "/usr/data/pellcorp/k1/bltouch.cfg" || exit $?

        if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
            cp /usr/data/pellcorp/k1/bltouch-k1.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "bltouch-k1.cfg" || exit $?
            $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "209" || exit $?
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/bltouch-k1m.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "bltouch-k1m.cfg" || exit $?
            $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "280" || exit $?
        fi

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
        echo "Setting up microprobe ..."
        
        cleanup_probe cartographer
        cleanup_probe bltouch
        cleanup_probe btteddy

        if [ -f /usr/data/printer_data/config/microprobe.cfg ]; then
          rm /usr/data/printer_data/config/microprobe.cfg
        fi
        $CONFIG_HELPER --remove-include "microprobe.cfg" || exit $?
        $CONFIG_HELPER --overrides "/usr/data/pellcorp/k1/microprobe.cfg" || exit $?

        if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
            cp /usr/data/pellcorp/k1/microprobe-k1.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "microprobe-k1.cfg" || exit $?
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/microprobe-k1m.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "microprobe-k1m.cfg" || exit $?
        fi
        
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
        echo "Setting up cartographer ..."

        cleanup_probe bltouch
        cleanup_probe microprobe
        cleanup_probe btteddy

        cp /usr/data/pellcorp/k1/cartographer_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartographer_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp /usr/data/pellcorp/k1/cartographer.cfg /usr/data/printer_data/config/ || exit $?

        CARTO_SERIAL_ID=$(ls /dev/serial/by-id/usb-Cartographer* | head -1)
        if [ "x$CARTO_SERIAL_ID" != "x" ]; then
            $CONFIG_HELPER --file cartographer.cfg --replace-section-entry "cartographer" "serial" "$CARTO_SERIAL_ID" || exit $?
        else
            echo "WARNING: There does not seem to be a cartographer attached - skipping auto configuration"
        fi

        $CONFIG_HELPER --add-include "cartographer.cfg" || exit $?

        if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
            cp /usr/data/pellcorp/k1/cartographer-k1.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "cartographer-k1.cfg" || exit $?
            $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "210" || exit $?
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/cartographer-k1m.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "cartographer-k1m.cfg" || exit $?
            $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "280" || exit $?
        fi

        echo "cartographer-probe" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

setup_btteddy() {
    grep -q "btteddy-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "Setting up btteddy ..."

        cleanup_probe bltouch
        cleanup_probe microprobe
        cleanup_probe cartographer

        cp /usr/data/pellcorp/k1/btteddy.cfg /usr/data/printer_data/config/ || exit $?
        
        BTTEDDY_SERIAL_ID=$(ls /dev/serial/by-id/usb-Klipper_rp2040* | head -1)
        if [ "x$BTTEDDY_SERIAL_ID" != "x" ]; then
            $CONFIG_HELPER --file btteddy.cfg --replace-section-entry "mcu eddy" "serial" "$BTTEDDY_SERIAL_ID" || exit $?
        else
            echo "WARNING: There does not seem to be a btt eddy attached - skipping auto configuration"
        fi
        $CONFIG_HELPER --add-include "btteddy.cfg" || exit $?

        cp /usr/data/pellcorp/k1/btteddy_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy_macro.cfg" || exit $?

        if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
            cp /usr/data/pellcorp/k1/btteddy-k1.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "btteddy-k1.cfg" || exit $?
            # the max for the current initial mount which is not really ideal
            $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "206" || exit $?
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/cartographer-k1m.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "btteddy-k1m.cfg" || exit $?
            $CONFIG_HELPER --replace-section-entry "stepper_y" "position_max" "276" || exit $?
        fi

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
        echo "Installing entware ..."
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
    echo "Restarting Moonraker ..."
    /etc/init.d/S56moonraker_service restart

    timeout=60
    start_time=$(date +%s)

    # this is mostly for k1-qemu where Moonraker takes a while to start up
    echo "Waiting for Moonraker ..."
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


mkdir -p /usr/data/pellcorp-backups
# so if the installer has never been run we should grab a backup of the printer.cfg
if [ ! -f /usr/data/pellcorp.done ] && [ ! -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
    cp /usr/data/printer_data/config/printer.cfg /usr/data/pellcorp-backups/printer.factory.cfg
fi

# figure out what existing probe if any is being used
probe=
if [ -f /usr/data/printer_data/config/bltouch-k1.cfg ] || [ -f /usr/data/printer_data/config/bltouch-k1m.cfg ]; then
    probe=bltouch
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
    elif [ "$1" = "microprobe" ] || [ "$1" = "bltouch" ] || [ "$1" = "cartographer" ] || [ "$1" = "btteddy" ]; then
        if [ -n "$probe" ] && [ "$1" != "$probe" ]; then
            echo ""
            echo "WARNING: About to switch from $probe to $1!"
        fi
        probe=$1
        shift
    elif [ -n "$1" ]; then # no more valid parameters
        echo "ERROR: You must specify a probe you want to configure"
        echo "One of: [microprobe, bltouch, cartographer, btteddy]"
        exit 1
    else # no more parameters
        break
    fi
done

if [ "$debug" = "true" ]; then
    echo "INFO: Mode is $mode"
    echo "INFO: Probe is $probe"
fi

if [ "$skip_overrides" = "true" ]; then
    echo "INFO: Configuration overrides will not be saved or applied"
fi

if [ "$mode" = "reinstall" ] || [ "$mode" = "update" ]; then
    if [ "$skip_overrides" != "true" ] && [ -f /usr/data/pellcorp-backups/printer.pellcorp.cfg ]; then
        /usr/data/pellcorp/k1/config-overrides.sh
    fi

    if [ -f /usr/data/pellcorp.done ]; then
      rm /usr/data/pellcorp.done
    fi

    # if we took a post factory reset backup for a reinstall restore it now
    if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
        cp /usr/data/pellcorp-backups/printer.factory.cfg /usr/data/printer_data/config/printer.cfg
        # for a reinstall need to trash that file
        if [ -f /usr/data/pellcorp-backups/printer.pellcorp.cfg ]; then
            rm /usr/data/pellcorp-backups/printer.pellcorp.cfg
        fi
    elif [ "$mode" = "update" ]; then
        echo "ERROR: Update mode is not available to users who have not done a factory reset since 27th of June 2024"
        exit 1
    fi
fi

touch /usr/data/pellcorp.done
cp /usr/data/printer_data/config/printer.cfg /usr/data/printer_data/config/.printer.cfg.bkp

install_config_updater
install_entware $mode

install_webcam

disable_creality_services

install_moonraker $mode
install_moonraker=$?

install_nginx
install_nginx=$?

install_fluidd $mode
install_fluidd=$?

install_mainsail
install_mainsail=$?

# KAMP is in the moonraker.conf file so it must be installed before moonraker is first started
install_kamp $mode
install_kamp=$?

install_klipper $mode
install_klipper=$?

# if moonraker was installed or updated
if [ $install_moonraker -ne 0 ]; then
    restart_moonraker
fi

if [ $install_klipper -ne 0 ] || [ $install_moonraker -ne 0 ] || [ $install_nginx -ne 0 ] || [ $install_fluidd -ne 0 ] || [ $install_mainsail -ne 0 ]; then
    echo ""
    echo "Restarting Nginx ..."
    /etc/init.d/S50nginx_service restart
fi

install_guppyscreen
install_guppyscreen=$?

setup_probe
setup_probe=$?

# installing carto must come after installing klipper
if [ "$probe" = "cartographer" ]; then
    setup_cartographer
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
if [ ! -f /usr/data/pellcorp-backups/printer.pellcorp.cfg ] && [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
    cp /usr/data/printer_data/config/printer.cfg /usr/data/pellcorp-backups/printer.pellcorp.cfg
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

if [ $apply_overrides -ne 0 ] || [ $install_kamp -ne 0 ] || [ $install_klipper -ne 0 ] || [ $install_guppyscreen -ne 0 ] || [ $setup_probe -ne 0 ] || [ $setup_probe_specific -ne 0 ]; then
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
