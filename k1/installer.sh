#!/bin/sh

KLIPPER_REPO=https://github.com/pellcorp/klipper.git

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

# special mode to update the repo only
if [ "$1" = "--update-repo" ]; then
    cd /usr/data/pellcorp
    branch_ref=$(git rev-parse --abbrev-ref HEAD)
    if [ -n "$branch_ref" ]; then
        git fetch
        git reset --hard origin/$branch_ref
        exit 0
    else
        echo "Failed to detect current branch"
        exit 1
    fi
fi

# kill pip cache to free up overlayfs
rm -rf /root/.cache

cp /usr/data/pellcorp/k1/services/S58factoryreset /etc/init.d || exit $?
sync

cp /usr/data/pellcorp/k1/services/S50dropbear /etc/init.d/ || exit $?
sync

# the api of the sh and the py is exactly the same
#CONFIG_HELPER=/usr/data/pellcorp/k1/config-helper.sh
CONFIG_HELPER="/usr/data/pellcorp-env/bin/python3 /usr/data/pellcorp/k1/config-helper.py"

# our little pellcorp python environment currently just for the config-helper.py
if [ ! -d /usr/data/pellcorp-env ]; then
    tar -zxf /usr/data/pellcorp/k1/pellcorp-env.tar.gz -C /usr/data/
    sync
fi

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

install_moonraker() {
    if ! grep -q "moonraker" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing moonraker ..."

        # lets allow reinstalls
        [ -d /usr/data/moonraker ] && rm -rf /usr/data/moonraker
        [ -d /usr/data/moonraker-env ] && rm -rf /usr/data/moonraker-env

        ln -sf /usr/data/pellcorp/k1/tools/supervisorctl /usr/bin/ || exit $?

        git clone https://github.com/Arksine/moonraker /usr/data/moonraker || exit $?
        cp /usr/data/pellcorp/k1/services/S56moonraker_service /etc/init.d/ || exit $?
        cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/ || exit $?
        cp /usr/data/pellcorp/k1/moonraker.asvc /usr/data/printer_data/ || exit $?
        cp /usr/data/pellcorp/k1/webcam.conf /usr/data/printer_data/config/ || exit $?
        cp /usr/data/pellcorp/k1/notifier.conf /usr/data/printer_data/config/ || exit $?
        cp /usr/data/pellcorp/k1/moonraker.secrets /usr/data/printer_data/ || exit $?
        tar -zxf /usr/data/pellcorp/k1/moonraker-env.tar.gz -C /usr/data/ || exit $?
        
        echo "moonraker" >> /usr/data/pellcorp.done
        sync
    fi
}

install_nginx() {
    if ! grep -q "nginx" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing nginx ..."

        # lets allow reinstalls
         [ -d /usr/data/nginx ] && rm -rf /usr/data/nginx

        tar -zxf /usr/data/pellcorp/k1/nginx.tar.gz -C /usr/data/ || exit $?
        cp /usr/data/pellcorp/k1/nginx.conf /usr/data/nginx/nginx/ || exit $?
        cp /usr/data/pellcorp/k1/services/S50nginx_service /etc/init.d/ || exit $?

        echo "nginx" >> /usr/data/pellcorp.done
        sync
    fi
}

install_fluidd() {
    if ! grep -q "fluidd" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing fluidd ..."

        # lets allow reinstalls
        [ -d /usr/data/fluidd ] && rm -rf /usr/data/fluidd

        mkdir -p /usr/data/fluidd || exit $? 
        /usr/data/pellcorp/k1/tools/curl -L "https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip" -o /usr/data/fluidd.zip || exit $?
        unzip -qd /usr/data/fluidd /usr/data/fluidd.zip || exit $?
        rm /usr/data/fluidd.zip
        
        /usr/data/pellcorp/k1/tools/curl -L "https://raw.githubusercontent.com/fluidd-core/fluidd-config/master/client.cfg" -o /usr/data/printer_data/config/fluidd.cfg || exit $?
        
        # we already define pause resume and virtual sd card in printer.cfg
        $CONFIG_HELPER --file fluidd.cfg --remove-section "pause_resume" || exit $?
        $CONFIG_HELPER --file fluidd.cfg --remove-section "virtual_sdcard" || exit $?
        $CONFIG_HELPER --file fluidd.cfg --remove-section "display_status" || exit $?

        $CONFIG_HELPER --add-include "fluidd.cfg" || exit $?
    
        echo "fluidd" >> /usr/data/pellcorp.done
        sync
    fi
}

install_mainsail() {
    if ! grep -q "mainsail" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing mainsail ..."

        # lets allow reinstalls
        [ -d /usr/data/mainsail ] && rm -rf /usr/data/mainsail
        
        mkdir -p /usr/data/mainsail || exit $?
        /usr/data/pellcorp/k1/tools/curl -L "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o /usr/data/mainsail.zip || exit $?
        unzip -qd /usr/data/mainsail /usr/data/mainsail.zip || exit $?
        rm /usr/data/mainsail.zip

        /usr/data/pellcorp/k1/tools/curl -L "https://raw.githubusercontent.com/mainsail-crew/mainsail-config/master/client.cfg" -o /usr/data/printer_data/config/mainsail.cfg || exit $?

        # we already define pause resume, display_status and virtual sd card in printer.cfg
        $CONFIG_HELPER --file mainsail.cfg --remove-section "pause_resume" || exit $?
        $CONFIG_HELPER --file mainsail.cfg --remove-section "virtual_sdcard" || exit $?
        $CONFIG_HELPER --file mainsail.cfg --remove-section "display_status" || exit $?

        # mainsail macros will conflict with fluidd ones
        # $CONFIG_HELPER --add-include "mainsail.cfg" || exit $?

        echo "mainsail" >> /usr/data/pellcorp.done
        sync
    fi
}

start_moonraker_nginx() {
    /etc/init.d/S56moonraker_service start
    /etc/init.d/S50nginx_service start
}

install_kamp() {
    if ! grep -q "KAMP" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing KAMP ..."

        # lets allow reinstalls
        [ -d /usr/data/KAMP ] && rm -rf /usr/data/KAMP

        git clone https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git /usr/data/KAMP || exit $?
        ln -s /usr/data/KAMP/Configuration/ /usr/data/printer_data/config/KAMP || exit $?
        cp /usr/data/KAMP/Configuration/KAMP_Settings.cfg /usr/data/printer_data/config/ || exit $?

        $CONFIG_HELPER --add-include "KAMP_Settings.cfg" || exit $?

        # enable KAMP line purge
        # FIXME - config-helper.py support enabling commented out entry maybe???
        sed -i 's:#\[include ./KAMP/Line_Purge.cfg\]:\[include ./KAMP/Line_Purge.cfg\]:g' /usr/data/printer_data/config/KAMP_Settings.cfg
        
        echo "KAMP" >> /usr/data/pellcorp.done
        sync
    fi
}

install_klipper() {
    if ! grep -q "klipper" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing klipper ..."

        # lets allow reinstalls
        [ -d /usr/data/klipper ] && rm -rf /usr/data/klipper

        git clone $KLIPPER_REPO /usr/data/klipper || exit $?

        [ -d /usr/share/klipper ] && rm -rf /usr/share/klipper
        ln -sf /usr/data/klipper /usr/share/ || exit $?

        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?
        cp /usr/data/pellcorp/k1/services/S55klipper_service /etc/init.d/ || exit $?
        
        # we have a local copy of this service which looks for fw in /usr/data/pellcorp/k1/fw instead
        # of in /usr/share/klipper/fw/K1
        cp /usr/data/pellcorp/k1/services/S13mcu_update /etc/init.d/ || exit $?

        cp /usr/data/pellcorp/k1/sensorless.cfg /usr/data/printer_data/config/ || exit $?

        $CONFIG_HELPER --remove-section "bl24c16f" || exit $?
        $CONFIG_HELPER --remove-section "mcu leveling_mcu" || exit $?
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

        $CONFIG_HELPER --remove-section "filament_switch_sensor filament_sensor_2" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan0" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan1" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan2" || exit $?

        echo "klipper" >> /usr/data/pellcorp.done
        sync
    fi
}

# originally I was using the guppyscreen installer, but it does a lot of stuff
# I already do in a slightly different way and it does stuff I really do not want
# to do, such as restart klipper because its a waste of time.
install_guppyscreen() {
    if ! grep -q "guppyscreen" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing guppyscreen ..."
        
        # lets allow reinstalls
        if [ -d /usr/data/guppyscreen ]; then
            if [ -f /etc/init.d/S99guppyscreen ]; then
                /etc/init.d/S99guppyscreen stop &> /dev/null
            fi
            killall -q guppyscreen
            
            rm -rf /usr/data/guppyscreen
        fi

        # guppyscreen requires this otherwise the compiled code wont work!!!
        if [ ! -f /lib/ld-2.29.so ]; then
            echo "ERROR: ld.so is not the expected version."
            exit 1
        fi

        # this is mostly for k1-qemu where moonraker takes a while to start up
        echo "Waiting for moonraker ..."
        while true; do
            KLIPPER_PATH=$(curl localhost:7125/printer/info 2> /dev/null | jq -r .result.klipper_path)
            if [ "$KLIPPER_PATH" = "/usr/share/klipper" ]; then
                break;
            fi
            sleep 1
        done

        /usr/data/pellcorp/k1/tools/curl -L "https://github.com/ballaswag/guppyscreen/releases/latest/download/guppyscreen.tar.gz" -o /usr/data/guppyscreen.tar.gz || exit $?
        tar xf /usr/data/guppyscreen.tar.gz  -C /usr/data/ || exit $?
        rm /usr/data/guppyscreen.tar.gz 
        cp /usr/data/guppyscreen/k1_mods/S99guppyscreen /etc/init.d/S99guppyscreen || exit $?

        if [ ! -d "/usr/lib/python3.8/site-packages/matplotlib-2.2.3-py3.8.egg-info" ]; then
            echo "WARNING: Not replacing mathplotlib ft2font module. PSD graphs might not work!"
        else
            cp /usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so /usr/lib/python3.8/site-packages/matplotlib/ || exit $?
        fi

        # for respawn command
        ln -sf /usr/data/guppyscreen/k1_mods/respawn/libeinfo.so.1 /lib/libeinfo.so.1 || exit $?
        ln -sf /usr/data/guppyscreen/k1_mods/respawn/librc.so.1 /lib/librc.so.1 || exit $?

        for file in gcode_shell_command.py guppy_config_helper.py calibrate_shaper_config.py guppy_module_loader.py tmcstatus.py; do
            ln -sf /usr/data/guppyscreen/k1_mods/$file /usr/share/klipper/klippy/extras/$file || exit $?
            if ! grep -q "klippy/extras/${file}" "/usr/share/klipper/.git/info/exclude"; then
                echo "klippy/extras/$file" >> "/usr/share/klipper/.git/info/exclude"
            fi
        done

        mkdir -p /usr/data/printer_data/config/GuppyScreen/scripts || exit $?
        cp /usr/data/guppyscreen/scripts/*.cfg /usr/data/printer_data/config/GuppyScreen/ || exit $?
        ln -sf /usr/data/guppyscreen/scripts/*.py /usr/data/printer_data/config/GuppyScreen/scripts/ || exit $?

        $CONFIG_HELPER --add-include "GuppyScreen/*.cfg" || exit $?
        
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        echo "guppyscreen" >> /usr/data/pellcorp.done
        sync
    fi
}

# generic probe stuff
setup_probe() {
    if ! grep -q "probe" /usr/data/pellcorp.done; then
        echo ""
        echo "Setting up generic probe config ..."

        $CONFIG_HELPER --remove-section "bed_mesh" || exit $?
        $CONFIG_HELPER --remove-section-entry "stepper_z" "position_endstop" || exit $?
        $CONFIG_HELPER --replace-section-entry "stepper_z" "endstop_pin" "probe:z_virtual_endstop" || exit $?
        echo "probe" >> /usr/data/pellcorp.done
    fi
}

setup_bltouch() {
    if ! grep -q "bltouch" /usr/data/pellcorp.done; then
        echo ""
        echo "Setting up bltouch ..."

        cp /usr/data/pellcorp/k1/bltouch.cfg /usr/data/printer_data/config/
        $CONFIG_HELPER --add-include "bltouch.cfg" || exit $?

        if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
            cp /usr/data/pellcorp/k1/bltouch-k1.cfg /usr/data/printer_data/config/
            $CONFIG_HELPER --add-include "bltouch-k1.cfg" || exit $?
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/bltouch-k1m.cfg /usr/data/printer_data/config/
            $CONFIG_HELPER --add-include "bltouch-k1m.cfg" || exit $?
        fi
        echo "bltouch" >> /usr/data/pellcorp.done
    fi
}

setup_microprobe() {
    if ! grep -q "microprobe" /usr/data/pellcorp.done; then
        echo ""
        echo "Setting up microprobe ..."

        cp /usr/data/pellcorp/k1/microprobe.cfg /usr/data/printer_data/config/
        $CONFIG_HELPER --add-include "microprobe.cfg" || exit $?

        if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ]; then
            cp /usr/data/pellcorp/k1/microprobe-k1.cfg /usr/data/printer_data/config/
            $CONFIG_HELPER --add-include "microprobe-k1.cfg" || exit $?
        elif [ "$MODEL" = "CR-K1 Max" ]; then
            cp /usr/data/pellcorp/k1/microprobe-k1m.cfg /usr/data/printer_data/config/
            $CONFIG_HELPER --add-include "microprobe-k1m.cfg" || exit $?
        fi
        echo "microprobe" >> /usr/data/pellcorp.done
    fi
}

# entware is handy for installing additional stuff, I see no harm in getting it setup ootb
install_entware() {
    if ! grep -q "entware" /usr/data/pellcorp.done; then
        echo ""
        echo "Installing entware ..."
        /usr/data/pellcorp/k1/install-entware.sh || exit $?

        echo "entware" >> /usr/data/pellcorp.done
    fi
}

touch /usr/data/pellcorp.done

disable_creality_services
install_moonraker
install_nginx
install_fluidd
install_mainsail
install_kamp

# we start moonraker and nginx late as the moonraker.conf and nginx.conf both reference fluidd and mainsail stuff that would 
# cause moonraker and nginx to fail if they were started any earlier.
start_moonraker_nginx

install_klipper
install_guppyscreen
setup_probe

if [ "$1" = "bltouch" ]; then
    setup_bltouch
else
    setup_microprobe
fi
install_entware

echo ""
echo "You MUST power cycle your printer to upgrade MCU firmware!"
exit 0

