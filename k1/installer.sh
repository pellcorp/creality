#!/bin/sh

# this is really just for my k1-qemu environment
if [ ! -f /usr/data/printer_data/config/printer.cfg ]; then
  >&2 echo "ERROR: Printer data not setup"
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
fi

# kill pip cache to free up overlayfs
rm -rf /root/.cache

cp /usr/data/pellcorp/k1/services/S58factoryreset /etc/init.d || exit $?
sync

cp /usr/data/pellcorp/k1/services/S50dropbear /etc/init.d/ || exit $?
sync

CONFIG_HELPER="/usr/data/pellcorp-env/bin/python3 /usr/data/pellcorp/k1/config-helper.py"

# our little pellcorp python environment currently just for the config-helper.py
if [ ! -d /usr/data/pellcorp-env ]; then
    tar -zxf /usr/data/pellcorp/k1/pellcorp-env.tar.gz -C /usr/data/
    sync
fi

setup_git_ssh() {
    mkdir -p /root/.ssh
    # this currently only supports klipper git clone via ssh as you can use a deploy key once
    cp /usr/data/pellcorp/k1/ssh/klipper-identity /root/.ssh/
    cp /usr/data/pellcorp/k1/ssh/git-ssh.sh /root/.git-ssh.sh
}

disable_creality_services() {
    if [ -f /etc/init.d/S99start_app ]; then
        echo ""
        echo "Disabling some creality services ..."

        echo "IMPORTANT: If you reboot the printer before installing guppyscreen, the screen will be blank - this is to be expected!"
        /etc/init.d/S99start_app stop

        [ -f /etc/init.d/S99start_app ] && rm /etc/init.d/S99start_app
        [ -f /etc/init.d/S70cx_ai_middleware ] && rm /etc/init.d/S70cx_ai_middleware
        [ -f /etc/init.d/S97webrtc ] && rm /etc/init.d/S97webrtc
        [ -f /etc/init.d/S99mdns ] && rm /etc/init.d/S99mdns
        [ -f /etc/init.d/S12boot_display ] && rm /etc/init.d/S12boot_display
        [ -f /etc/init.d/S96wipe_data ] && rm /etc/init.d/S96wipe_data

        sync
    fi
}

install_webcam() {
    grep -q "webcam" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing web camera streamer ..."
        /opt/bin/opkg install mjpg-streamer mjpg-streamer-input-http mjpg-streamer-input-uvc mjpg-streamer-output-http mjpg-streamer-www || exit $?

        # kill the existing creality services so that we can use the app right away without a restart
        pidof cam_app &>/dev/null && killall -TERM cam_app
        pidof mjpg_streamer &>/dev/null && killall -TERM mjpg_streamer

        # auto_uvc.sh is responsible for starting the web cam_app
        [ -f /usr/bin/auto_uvc.sh ] && rm /usr/bin/auto_uvc.sh
        # create an empty script to avoid udev getting upset
        touch /usr/bin/auto_uvc.sh
        chmod 777 /usr/bin/auto_uvc.sh

        cp /usr/data/pellcorp/k1/services/S50webcam /etc/init.d/
        /etc/init.d/S50webcam start
        echo "webcam" >> /usr/data/pellcorp.done
        sync
        return 0
    fi
    return 0
}

install_moonraker() {
    local mode=$1

    grep -q "moonraker" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        if [ "$mode" = "update" ]; then
            echo "Updating moonraker ..."
            
            update_repo /usr/data/moonraker
        else
            echo "Installing moonraker ..."

            if [ -d /usr/data/moonraker ]; then
                if [ -f /etc/init.d/S56moonraker_service ]; then
                    /etc/init.d/S56moonraker_service stop
                fi
                if [ -d /usr/data/printer_data/database/ ]; then
                    [ -f  /usr/data/moonraker-database.tar.gz ] && rm  /usr/data/moonraker-database.tar.gz

                    # TODO - a reinstall will backup the moonraker database but nothing else
                    # and there is no way to avoid backing it up at this point, I guess I can 
                    # add a dock or a command line option to remove the db before the install begins
                    echo ""
                    echo "Backing up moonraker database ..."
                    cd /usr/data/printer_data/

                    # an existing bug where the moonraker secrets was not correctly copied
                    if [ ! -f moonraker.secrets ]; then
                        cp /usr/data/pellcorp/k1/moonraker.secrets .
                    fi
                    tar -zcf /usr/data/moonraker-database.tar.gz database/ moonraker.secrets
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

        ln -sf /usr/data/pellcorp/k1/tools/supervisorctl /usr/bin/ || exit $?
        tar -zxf /usr/data/pellcorp/k1/moonraker-env.tar.gz -C /usr/data/ || exit $?

        cp /usr/data/pellcorp/k1/services/S56moonraker_service /etc/init.d/ || exit $?
        cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/ || exit $?
        cp /usr/data/pellcorp/k1/moonraker.asvc /usr/data/printer_data/ || exit $?
        
        # after an initial install do not overwrite notifier.conf or moonraker.secrets
        if [ ! -f /usr/data/printer_data/config/notifier.conf ]; then
            cp /usr/data/pellcorp/k1/notifier.conf /usr/data/printer_data/config/
        fi
        if [ ! -f /usr/data/printer_data/moonraker.secrets ]; then
            cp /usr/data/pellcorp/k1/moonraker.secrets /usr/data/printer_data/
        fi

        if [ "$mode" != "update" ]; then
            cp /usr/data/pellcorp/k1/webcam.conf /usr/data/printer_data/config/ || exit $?

            echo "moonraker" >> /usr/data/pellcorp.done
        fi
        sync

        # means nginx and moonraker need to be restarted
        return 1
    fi
    return 0
}

install_nginx() {
    local mode=$1

    grep -q "nginx" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        if [ "$mode" = "update" ]; then
            echo "Updating nginx ..."
        else
            echo "Installing nginx ..."
        fi

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

        if [ "$mode" != "update" ]; then
            echo "nginx" >> /usr/data/pellcorp.done
        fi
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

install_fluidd() {
    local mode=$1

    grep -q "fluidd" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        if [ "$mode" = "update" ]; then
            echo "Updating fluidd ..."

            if [ -d /usr/data/fluidd-config ]; then
                update_repo /usr/data/fluidd-config
            else
                git clone https://github.com/fluidd-core/fluidd-config.git /usr/data/fluidd-config || exit $?
            fi
        else
            echo "Installing fluidd ..."

            [ -d /usr/data/fluidd ] && rm -rf /usr/data/fluidd

            mkdir -p /usr/data/fluidd || exit $? 
            /usr/data/pellcorp/k1/tools/curl -L "https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip" -o /usr/data/fluidd.zip || exit $?
            unzip -qd /usr/data/fluidd /usr/data/fluidd.zip || exit $?
            rm /usr/data/fluidd.zip

            [ -d /usr/data/fluidd-config ] && rm -rf /usr/data/fluidd-config
            git clone https://github.com/fluidd-core/fluidd-config.git /usr/data/fluidd-config
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

        if [ "$mode" != "update" ]; then
            echo "fluidd" >> /usr/data/pellcorp.done
        fi
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

install_mainsail() {
    local mode=$1

    grep -q "mainsail" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        if [ "$mode" = "update" ]; then
            echo "Updating mainsail ..."
        else
            echo "Installing mainsail ..."

            [ -d /usr/data/mainsail ] && rm -rf /usr/data/mainsail
            
            mkdir -p /usr/data/mainsail || exit $?
            /usr/data/pellcorp/k1/tools/curl -L "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o /usr/data/mainsail.zip || exit $?
            unzip -qd /usr/data/mainsail /usr/data/mainsail.zip || exit $?
            rm /usr/data/mainsail.zip
        fi

        # the mainsail and fluidd client.cfg are exactly the same
        [ -f /usr/data/printer_data/config/mainsail.cfg ] && rm /usr/data/printer_data/config/mainsail.cfg

        if [ "$mode" != "update" ]; then
            echo "mainsail" >> /usr/data/pellcorp.done
        fi
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

install_kamp() {
    local mode=$1

    grep -q "KAMP" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        if [ "$mode" = "update" ]; then
            echo "Updating KAMP ..."
            
            update_repo /usr/data/KAMP
        else
            echo "Installing KAMP ..."

            # lets allow reinstalls
            [ -d /usr/data/KAMP ] && rm -rf /usr/data/KAMP

            git clone https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git /usr/data/KAMP || exit $?
        fi

        ln -sf /usr/data/KAMP/Configuration/ /usr/data/printer_data/config/KAMP || exit $?

        if [ "$mode" != "update" ]; then
            cp /usr/data/KAMP/Configuration/KAMP_Settings.cfg /usr/data/printer_data/config/ || exit $?
        fi

        $CONFIG_HELPER --add-include "KAMP_Settings.cfg" || exit $?

        # LINE_PURGE
        sed -i 's:#\[include ./KAMP/Line_Purge.cfg\]:\[include ./KAMP/Line_Purge.cfg\]:g' /usr/data/printer_data/config/KAMP_Settings.cfg

        # SMART_PARK
        sed -i 's:#\[include ./KAMP/Smart_Park.cfg\]:\[include ./KAMP/Smart_Park.cfg\]:g' /usr/data/printer_data/config/KAMP_Settings.cfg

        if [ "$mode" != "update" ]; then
            echo "KAMP" >> /usr/data/pellcorp.done
        fi
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

install_klipper() {
    local mode=$1

    grep -q "klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""

        if [ -f /etc/init.d/S57klipper_mcu ]; then
            /etc/init.d/S55klipper_service stop
            /etc/init.d/S57klipper_mcu stop
            rm /etc/init.d/S57klipper_mcu
            /etc/init.d/S55klipper_service start
        fi

        if [ "$mode" = "update" ]; then
            echo "Updating klipper ..."

            update_repo /usr/data/klipper
        else
            echo "Installing klipper ..."

            if [ -d /usr/data/klipper ]; then
                if [ -f /etc/init.d/S55klipper_service ]; then
                    /etc/init.d/S55klipper_service stop
                fi
                rm -rf /usr/data/klipper
            fi
            
            # this is only for testing with crappy internet
            if [ "$KLIPPER_GIT_CLONE" = "ssh" ]; then
                export GIT_SSH_IDENTITY=klipper
                export GIT_SSH=$HOME/.git-ssh.sh
                git clone git@github.com:pellcorp/klipper.git /usr/data/klipper || exit $?
                # reset the origin url to make moonraker happy
                cd /usr/data/klipper && git remote set-url origin https://github.com/pellcorp/klipper.git && cd - > /dev/null
            else
                git clone https://github.com/pellcorp/klipper.git /usr/data/klipper || exit $?
            fi
            [ -d /usr/share/klipper ] && rm -rf /usr/share/klipper
        fi

        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?
        ln -sf /usr/data/klipper /usr/share/ || exit $?
        cp /usr/data/pellcorp/k1/services/S55klipper_service /etc/init.d/ || exit $?

        cp /usr/data/pellcorp/k1/services/S13mcu_update /etc/init.d/ || exit $?

        cp /usr/data/pellcorp/k1/sensorless.cfg /usr/data/printer_data/config/ || exit $?

        # the klipper_mcu is not even used, so just get rid of it
        $CONFIG_HELPER --remove-section "mcu rpi" || exit $?

        $CONFIG_HELPER --remove-section "bl24c16f" || exit $?
        $CONFIG_HELPER --remove-section "prtouch_v2" || exit $?
        $CONFIG_HELPER --remove-section-entry "printer" "square_corner_max_velocity" || exit $?
        $CONFIG_HELPER --remove-section-entry "printer" "max_accel_to_decel" || exit $?

        $CONFIG_HELPER --remove-include "printer_params.cfg" || exit $?
        $CONFIG_HELPER --remove-include "gcode_macro.cfg" || exit $?

        if [ -f /usr/data/printer_data/config/gcode_macro.cfg ]; then
            rm /usr/data/printer_data/config/gcode_macro.cfg
        fi

        if [ -f /usr/data/printer_data/config/printer_params.cfg ]; then
            rm /usr/data/printer_data/config/printer_params.cfg
        fi

        if [ -f /usr/data/printer_data/config/factory_printer.cfg ]; then
            rm /usr/data/printer_data/config/factory_printer.cfg
        fi

        cp /usr/data/pellcorp/k1/custom_gcode.cfg /usr/data/printer_data/config/custom_gcode.cfg || exit $?
        $CONFIG_HELPER --add-include "custom_gcode.cfg" || exit $?

        # proper fan control
        cp /usr/data/pellcorp/k1/fan_control.cfg /usr/data/printer_data/config || exit $?
        $CONFIG_HELPER --add-include "fan_control.cfg" || exit $?

        $CONFIG_HELPER --remove-section "output_pin fan0" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan1" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan2" || exit $?
        
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

        if [ "$mode" != "update" ]; then
            echo "klipper" >> /usr/data/pellcorp.done
        fi

        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

install_guppyscreen() {
    local mode=$1

    grep -q "guppyscreen" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        if [ "$mode" = "update" ]; then
            echo "Updating guppyscreen ..."
        else
            echo "Installing guppyscreen ..."
        fi

        if [ -d /usr/data/guppyscreen ]; then
            if [ -f /etc/init.d/S99guppyscreen ]; then
                /etc/init.d/S99guppyscreen stop &> /dev/null
            fi
            killall -q guppyscreen
            
            rm -rf /usr/data/guppyscreen
        fi
    
        /usr/data/pellcorp/k1/tools/curl -L "https://github.com/ballaswag/guppyscreen/releases/latest/download/guppyscreen.tar.gz" -o /usr/data/guppyscreen.tar.gz || exit $?
        tar xf /usr/data/guppyscreen.tar.gz  -C /usr/data/ || exit $?
        rm /usr/data/guppyscreen.tar.gz 
        cp /usr/data/pellcorp/k1/services/S99guppyscreen /etc/init.d/ || exit $?
        cp /usr/data/pellcorp/k1/guppyscreen/guppyconfig.json /usr/data/guppyscreen || exit $?

        if [ ! -d "/usr/lib/python3.8/site-packages/matplotlib-2.2.3-py3.8.egg-info" ]; then
            echo "WARNING: Not replacing mathplotlib ft2font module. PSD graphs might not work!"
        else
            cp /usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so /usr/lib/python3.8/site-packages/matplotlib/ || exit $?
        fi
        
        for file in guppy_config_helper.py calibrate_shaper_config.py guppy_module_loader.py tmcstatus.py; do
            ln -sf /usr/data/guppyscreen/k1_mods/$file /usr/data/klipper/klippy/extras/$file || exit $?
            if ! grep -q "klippy/extras/${file}" "/usr/data/klipper/.git/info/exclude"; then
                echo "klippy/extras/$file" >> "/usr/data/klipper/.git/info/exclude"
            fi
        done
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?
        
        # get rid of the old guppyscreen config
        [ -d /usr/data/printer_data/config/GuppyScreen ] && rm -rf /usr/data/printer_data/config/GuppyScreen

        cp /usr/data/pellcorp/k1/guppyscreen/guppyscreen.cfg /usr/data/printer_data/config/ || exit $?

        # a single local guppyscreen.cfg which references the python files from /usr/data/guppyscreen instead
        $CONFIG_HELPER --remove-include "GuppyScreen/*.cfg" || exit $?
        $CONFIG_HELPER --add-include "guppyscreen.cfg" || exit $?

        if [ "$mode" != "update" ]; then
            echo "guppyscreen" >> /usr/data/pellcorp.done
        fi
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

# regardless of probe choice just install the repo
install_cartographer_klipper() {
    grep -q "cartographer-klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        if [ "$mode" = "update" ]; then
            if [ -d /usr/data/cartographer-klipper ]; then
                update_repo /usr/data/cartographer-klipper
            else
                git clone https://github.com/pellcorp/cartographer-klipper.git /usr/data/cartographer-klipper || exit $?
            fi
        else
            echo "Installing cartographer-klipper ..."
            
            if [ -d /usr/data/cartographer-klipper ]; then
                rm -rf /usr/data/cartographer-klipper
            fi
            
            git clone https://github.com/pellcorp/cartographer-klipper.git /usr/data/cartographer-klipper || exit $?
        fi

        echo "Running cartographer-klipper installer ..."
        /usr/data/cartographer-klipper/install.sh || exit $?
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        if [ "$mode" != "update" ]; then
            echo "cartographer-klipper" >> /usr/data/pellcorp.done
        fi
        sync
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
    local mode=$1
    grep -q "bltouch-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        echo "Setting up bltouch ..."

        cleanup_probe cartographer
        cleanup_probe microprobe

        cp /usr/data/pellcorp/k1/bltouch.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "bltouch.cfg" || exit $?

        if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
            cp /usr/data/pellcorp/k1/bltouch-k1.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "bltouch-k1.cfg" || exit $?
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/bltouch-k1m.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "bltouch-k1m.cfg" || exit $?
        fi

        if [ "$mode" != "update" ]; then
            echo "bltouch-probe" >> /usr/data/pellcorp.done
        fi
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

setup_microprobe() {
    local mode=$1

    grep -q "microprobe-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        echo "Setting up microprobe ..."
        
        cleanup_probe cartographer
        cleanup_probe bltouch

        cp /usr/data/pellcorp/k1/microprobe.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "microprobe.cfg" || exit $?

        if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
            cp /usr/data/pellcorp/k1/microprobe-k1.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "microprobe-k1.cfg" || exit $?
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/microprobe-k1m.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "microprobe-k1m.cfg" || exit $?
        fi
        
        if [ "$mode" != "update" ]; then
            echo "microprobe-probe" >> /usr/data/pellcorp.done
        fi
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

setup_cartographer() {
    local mode=$1

    grep -q "cartographer-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        echo ""
        echo "Setting up cartographer ..."

        cleanup_probe bltouch
        cleanup_probe microprobe

        cp /usr/data/pellcorp/k1/cartographer/cartographer_macro.cfg /usr/data/printer_data/config/ || exit $?
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
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/cartographer-k1m.cfg /usr/data/printer_data/config/ || exit $?
            $CONFIG_HELPER --add-include "cartographer-k1m.cfg" || exit $?
        fi

        if [ "$mode" != "update" ]; then
            echo "cartographer-probe" >> /usr/data/pellcorp.done
        fi
        sync
        return 1
    fi
    return 0
}

install_entware() {
    if ! grep -q "entware" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing entware ..."
        /usr/data/pellcorp/k1/entware-install.sh || exit $?

        echo "entware" >> /usr/data/pellcorp.done
        sync
    fi
}

function apply_overrides() {
    return_status=0
    grep -q "overrides" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "update" ]; then
        if [ -f /usr/data/pellcorp-overrides.cfg ] || [ -d /usr/data/pellcorp-overrides ]; then
            echo ""
            echo "Applying overrides ..."

            overrides_dir=/usr/data/pellcorp-overrides
            if [ -f /usr/data/pellcorp-overrides.cfg ]; then
                overrides_dir=/tmp/overrides.$$
                mkdir $overrides_dir
                file=
                while IFS= read -r line; do
                    echo "$line" | grep -q "\--"
                    if [ $? -eq 0 ]; then
                        file=$(echo $line | sed 's/-- //g')
                        touch $overrides_dir/$file
                    elif [ -n "$file" ] && [ -f $overrides_dir/$file ]; then
                        echo "$line" >> $overrides_dir/$file
                    fi
                done < "/usr/data/pellcorp-overrides.cfg"
            fi

            files=$(ls $overrides_dir)
            for file in $files; do
                echo "Applying overrides for $file"
                # special case for moonraker.secrets
                if [ "$file" = "moonraker.secrets" ]; then
                    cp $overrides_dir/$file /usr/data/printer_data/
                else
                    cp /usr/data/printer_data/config/$file /usr/data/printer_data/config/${file}.override.bkp
                    $CONFIG_HELPER --file $file --overrides $overrides_dir/$file
                fi
                # fixme - we currently have no way to know if the file was updated assume if we got here it was
                return_status=1
            done

            if [ -d /tmp/overrides.$$ ]; then
                rm -rf /tmp/overrides.$$
            fi

            if [ "$mode" != "update" ]; then
                echo "overrides" >> /usr/data/pellcorp.done
            fi
            sync
        fi
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
            echo "Timeout reached. Moonraker failed to start within $timeout seconds."
            break;
        fi
        sleep 1
    done
}

mode=install
if [ "$1" = "--reinstall" ]; then
    rm /usr/data/pellcorp.done
    mode=reinstall
    shift
elif [ "$1" = "--update" ]; then
    mode=update
    shift
fi

probe=
if [ -f /usr/data/printer_data/config/bltouch.cfg ]; then
    probe=bltouch
elif [ -f /usr/data/printer_data/config/cartographer.cfg ]; then
    probe=cartographer
elif [ -f /usr/data/printer_data/config/microprobe.cfg ]; then
    probe=microprobe
fi

if [ "$1" = "microprobe" ] || [ "$1" = "bltouch" ] || [ "$1" = "cartographer" ]; then
    if [ "x$probe" != "x" ] && [ "$1" != "$probe" ]; then
        echo ""
        echo "WARNING: About to switch from $probe to $1!"
    fi
    probe=$1
elif [ "x$probe" = "x" ]; then
    echo "ERROR: You must specify a probe you want to configure"
    echo "One of: [microprobe, bltouch, cartographer]"
    exit 1
fi

touch /usr/data/pellcorp.done

cp /usr/data/printer_data/config/printer.cfg /usr/data/printer_data/config/printer.cfg.bkp

setup_git_ssh
install_entware

install_webcam

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

install_klipper $mode
install_klipper=$?

install_cartographer_klipper
install_cartographer_klipper=$?

# if moonraker was installed or updated
if [ $install_moonraker -ne 0 ]; then
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
    setup_cartographer $mode
    setup_probe_specific=$?
elif [ "$probe" = "bltouch" ]; then
    setup_bltouch $mode
    setup_probe_specific=$?
else # microprobe
    setup_microprobe $mode
    setup_probe_specific=$?
fi

apply_overrides $mode
apply_overrides=$?

# just restart moonraker in case any overrides were applied
if [ $apply_overrides -ne 0 ]; then
    restart_moonraker
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

if [ "$mode" != "update" ]; then
    echo ""
    echo "You MUST power cycle your printer to upgrade MCU firmware!"
fi

exit 0
