#!/bin/sh

if [ ! -f /usr/data/printer_data/config/printer.cfg ]; then
  >&2 echo "ERROR: Printer data not setup"
  exit 1
fi

MODEL=$(/usr/bin/get_sn_mac.sh model)
if [ "$MODEL" != "CR-K1" ]; then
    echo "Currently this script is only supported for the original K1!"
    exit 1
fi

if [ -d /usr/data/helper-script ]; then
    echo "The Guilouz helper script cannot be installed"
    exit 1
fi

if [ -f /usr/data/fluidd.sh ]; then
    echo "The K1_Series_Annex scripts cannot be installed"
    exit 1
fi

if [ -f /usr/data/mainsail.sh ]; then
    echo "The K1_Series_Annex scripts cannot be installed"
    exit 1
fi

# https://stackoverflow.com/a/1638397
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

if [ "$SCRIPTPATH" != "/usr/data/pellcorp/k1" ]; then
  >&2 echo "ERROR: This git repo must be cloned to /usr/data/pellcorp"
fi

if [ ! -f /etc/init.d/S58factoryreset ]; then
    # my root image has out of date S51factoryreset 
    if [ -f /etc/init.d/S51factoryreset ]; then
        rm /etc/init.d/S51factoryreset
    fi
    cp /usr/data/pellcorp/k1/S58factoryreset /etc/init.d
    sync
fi

install_moonraker() {
    grep "moonraker" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing moonraker ..."
        git clone https://github.com/Arksine/moonraker /usr/data/moonraker || exit $?
        cp /usr/data/pellcorp/k1/S56moonraker_service /etc/init.d/
        cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/
        cp /usr/data/pellcorp/k1/notifier.conf /usr/data/printer_data/config/
        cp /usr/data/pellcorp/k1/moonraker.secrets /usr/data/printer_data/
        tar -zxf /usr/data/pellcorp/k1/moonraker-env.tar.gz -C /usr/data/ || exit $?
        echo "moonraker" >> /usr/data/pellcorp.done
        sync
    fi
}

install_nginx() {
    grep "nginx" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing nginx ..."
        tar -zxf /usr/data/pellcorp/k1/nginx.tar.gz -C /usr/data/ || exit $?
        cp /usr/data/pellcorp/k1/nginx.conf /usr/data/nginx/nginx/
        cp /usr/data/pellcorp/k1/S50nginx_service /etc/init.d/
        echo "nginx" >> /usr/data/pellcorp.done
        sync
    fi
}

disable_creality_services() {
    grep "creality" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Disabling some creality services ..."
        echo "IMPORTANT: If you reboot the printer before installing guppyscreen, the screen will be blank - this is to be expected!"
        mkdir -p /usr/data/backup
        /etc/init.d/S99start_app stop
        mv /etc/init.d/S99start_app /usr/data/backup
        mv /etc/init.d/S70cx_ai_middleware /usr/data/backup/
        mv /etc/init.d/S97webrtc /usr/data/backup/
        mv /etc/init.d/S99mdns /usr/data/backup/
        mv /etc/init.d/S12boot_display /usr/data/backup/
        # we have our own factory reset service we dont need this one
        mv /etc/init.d/S96wipe_data /usr/data/backup/
        cp /usr/data/printer_data/config/printer.cfg /usr/data/backup/
        echo "creality" >> /usr/data/pellcorp.done
        sync
    fi
}

install_fluidd() {
    grep "fluidd" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing fluidd ..."
        mkdir -p /usr/data/fluidd 
        # thanks to Guilouz for pointing out the url I can use to get the latest version
        /usr/data/pellcorp/k1/curl -s -L "https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip" -o /usr/data/fluidd.zip || exit $?
        unzip -qd /usr/data/fluidd /usr/data/fluidd.zip || exit $?
        rm /usr/data/fluidd.zip
        
        /usr/data/pellcorp/k1/curl -s -L "https://raw.githubusercontent.com/fluidd-core/fluidd-config/master/client.cfg" -o /usr/data/printer_data/config/fluidd.cfg || exit $?
        # we already define pause resume and virtual sd card in printer.cfg
        sed -i '/^\[pause_resume\]/,/^$/d' /usr/data/printer_data/config/fluidd.cfg || exit $?
        sed -i '/^\[virtual_sdcard\]/,/^$/d' /usr/data/printer_data/config/fluidd.cfg || exit $?
    
        sed -i '/\[include gcode_macro\.cfg\]/a \[include fluidd\.cfg\]' /usr/data/printer_data/config/printer.cfg || exit $?
    
        echo "fluidd" >> /usr/data/pellcorp.done
        sync
    fi
}

install_mainsail() {
    grep "mainsail" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing mainsail ..."
        mkdir -p /usr/data/mainsail 
        /usr/data/pellcorp/k1/curl -s -L "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o /usr/data/mainsail.zip || exit $?
        echo "mainsail" >> /usr/data/pellcorp.done
        sync
    fi
}

start_moonraker_nginx() {
    /etc/init.d/S56moonraker_service start
    /etc/init.d/S50nginx_service start
}

install_klipper() {
    grep "klipper" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing klipper ..."
        mkdir -p /usr/data/backup
        git clone https://github.com/pellcorp/klipper.git /usr/data/klipper || exit $?
        cd /usr/data/klipper
        rm -rf /usr/share/klipper
        # can restore this with (thanks to Guilouz for pointing this out):
        # rm -rf /overlay/upper/usr/share/klipper
        # mount -o remount /
        mv /usr/data/printer_data/config/sensorless.cfg /usr/data/backup/
        ln -s /usr/data/klipper /usr/share/
        cp /usr/data/pellcorp/k1/sensorless.cfg /usr/data/printer_data/config/
        mv /etc/init.d/S55klipper_service /usr/data/backup/
        cp /usr/data/pellcorp/k1/S55klipper_service /etc/init.d/
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        sed -i '/^\[bl24c16f\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[mcu leveling_mcu\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[prtouch_v2\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^square_corner_max_velocity: 200.0$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^max_accel_to_decel.*/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i 's/^\[include gcode_macro\.cfg\]/#\[include gcode_macro\.cfg\]/g' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i 's/^\[include printer_params\.cfg\]/#\[include printer_params\.cfg\]/g' /usr/data/printer_data/config/printer.cfg || exit $?

        # proper fan control
        cp /usr/data/pellcorp/k1/fan_control.cfg /usr/data/printer_data/config
        sed -i '/\[include gcode_macro\.cfg\]/a \[include fan_control\.cfg\]' /usr/data/printer_data/config/printer.cfg
        
        sed -i '/^\[filament_switch_sensor filament_sensor_2\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[output_pin fan0\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[output_pin fan1\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[output_pin fan2\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?

        cp /usr/data/pellcorp/k1/custom_gcode.cfg /usr/data/printer_data/config
        sed -i '/\[include gcode_macro\.cfg\]/a \[include custom_gcode\.cfg\]' /usr/data/printer_data/config/printer.cfg || exit $?

        echo "klipper" >> /usr/data/pellcorp.done
        echo "WARNING: A power cycle is required to properly activate klipper!"
        sync
    fi
}

install_guppyscreen() {
    grep "guppyscreen" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing guppyscreen ..."
        
        echo "Waiting for moonraker ..."
        while true; do
            KLIPPER_PATH=$(curl localhost:7125/printer/info 2> /dev/null | jq -r .result.klipper_path)
            if [ "$KLIPPER_PATH" = "/usr/share/klipper" ]; then
                break;
            fi
            sleep 1
        done

        # guppyscreen won't try and backup anything if this directory already exists, since I already backed everything up
        # already I want guppyscreen installer to skip it.
        mkdir -p /usr/data/guppyify-backup

        /usr/data/pellcorp/k1/curl -s -L "https://raw.githubusercontent.com/ballaswag/guppyscreen/main/installer.sh" -o /usr/data/guppy-installer.sh || exit $?
        chmod 777 /usr/data/guppy-installer.sh

        # we have aleady removed the creality services, so we dont need guppy to do that for us
        sed -i 's/read confirm_decreality/confirm_decreality=n/g' /usr/data/guppy-installer.sh || exit $?

        # so we don't need guppyscreen to restart klipper as we are going to power cycle the printer
        sed -i 's/read confirm/confirm=n/g' /usr/data/guppy-installer.sh || exit $?
        
        /usr/data/guppy-installer.sh || exit $?
        rm /usr/data/guppy-installer.sh
        
        # guppyscreen installs some new python stuff so compile that stuff now
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy
        echo "guppyscreen" >> /usr/data/pellcorp.done
    fi
}

# generic probe stuff
setup_probe() {
    grep "probe" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Setting up generic probe config ..."
        sed -i '/^\[bed_mesh\]/,/^$/d' /usr/data/printer_data/config/printer.cfg
        sed -i 's/^endstop_pin: tmc2209_stepper_z:virtual_endstop.*/endstop_pin: probe:z_virtual_endstop/g' /usr/data/printer_data/config/printer.cfg
        sed -i '/^position_endstop: 0$/d' /usr/data/printer_data/config/printer.cfg
        echo "probe" >> /usr/data/pellcorp.done
    fi
}

setup_bltouch() {
    grep "bltouch" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Setting up bltouch ..."
        cp /usr/data/pellcorp/k1/bltouch.cfg /usr/data/printer_data/config/
        sed -i '/\[include gcode_macro\.cfg\]/a \[include bltouch\.cfg\]' /usr/data/printer_data/config/printer.cfg || exit $?
        echo "bltouch" >> /usr/data/pellcorp.done
    fi
}

setup_microprobe() {
    grep "microprobe" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Setting up microprobe ..."
        cp /usr/data/pellcorp/k1/microprobe.cfg /usr/data/printer_data/config/
        sed -i '/\[include gcode_macro\.cfg\]/a \[include microprobe\.cfg\]' /usr/data/printer_data/config/printer.cfg || exit $?
        echo "microprobe" >> /usr/data/pellcorp.done
    fi
}

touch /usr/data/pellcorp.done

install_moonraker
install_nginx
disable_creality_services
install_fluidd
# we start moonraker and nginx late as the moonraker.conf and nginx.conf both reference fluidd stuff that would 
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

echo ""
echo "Please power cycle your printer to activate updated klipper and perform any nozzle firmware update!"
exit 0
