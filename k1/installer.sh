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

disable_creality_services() {
    grep "creality" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Disabling some creality services ..."

        echo "IMPORTANT: If you reboot the printer before installing guppyscreen, the screen will be blank - this is to be expected!"
        /etc/init.d/S99start_app stop
        mv /etc/init.d/S99start_app /usr/data/backup 2> /dev/null
        mv /etc/init.d/S70cx_ai_middleware /usr/data/backup/p 2> /dev/null
        mv /etc/init.d/S97webrtc /usr/data/backup/p 2> /dev/null
        mv /etc/init.d/S99mdns /usr/data/backup/p 2> /dev/null
        mv /etc/init.d/S12boot_display /usr/data/backup/p 2> /dev/null
        # we have our own factory reset service we dont need this one
        mv /etc/init.d/S96wipe_data /usr/data/backup/p 2> /dev/null
        
        echo "creality" >> /usr/data/pellcorp.done
        sync
    fi
}

# not strictly necessary but handy to have backups if we need to 
# on the spot tweak something, especially if a user has an issue
# and I am trying diagnose issue over discord
backup_config() {
    mkdir -p /usr/data/backup
    
    if [ ! -f /usr/data/backup/printer.cfg ]; then
        cp /usr/data/printer_data/config/printer.cfg /usr/data/backup/
    fi

    if [ ! -f /usr/data/backup/sensorless.cfg ]; then
        cp /usr/data/printer_data/config/sensorless.cfg /usr/data/backup/
    fi

    if [ ! -f /usr/data/backup/gcode_macro.cfg ]; then
        cp /usr/data/printer_data/config/gcode_macro.cfg /usr/data/backup/
    fi

    if [ -f /usr/data/printer_data/config/printer_params.cfg ]; then
        mv /usr/data/printer_data/config/printer_params.cfg /usr/data/backup/
    fi

    if [ -f /usr/data/printer_data/config/factory_printer.cfg ]; then
        mv /usr/data/printer_data/config/factory_printer.cfg /usr/data/backup/
    fi

    if [ ! -f /usr/data/backup/S55klipper_service ]; then
        cp /etc/init.d/S55klipper_service /usr/data/backup/
    fi
}

install_moonraker() {
    grep "moonraker" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing moonraker ..."

        # lets allow reinstalls
        if [ -d /usr/data/moonraker ]; then
            rm -rf /usr/data/moonraker
        fi
        if [ -d /usr/data/moonraker-env ]; then
            rm -rf /usr/data/moonraker-env
        fi
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

        # lets allow reinstalls
        if [ -d /usr/data/nginx ]; then
            rm -rf /usr/data/nginx
        fi
        tar -zxf /usr/data/pellcorp/k1/nginx.tar.gz -C /usr/data/ || exit $?
        cp /usr/data/pellcorp/k1/nginx.conf /usr/data/nginx/nginx/
        cp /usr/data/pellcorp/k1/S50nginx_service /etc/init.d/
        echo "nginx" >> /usr/data/pellcorp.done
        sync
    fi
}

install_fluidd() {
    grep "fluidd" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing fluidd ..."

        # lets allow reinstalls
        if [ -d /usr/data/fluidd ]; then
            rm -rf /usr/data/fluidd
        fi
        mkdir -p /usr/data/fluidd 
        # thanks to Guilouz for pointing out the url I can use to get the latest version
        /usr/data/pellcorp/k1/curl -s -L "https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip" -o /usr/data/fluidd.zip || exit $?
        unzip -qd /usr/data/fluidd /usr/data/fluidd.zip || exit $?
        rm /usr/data/fluidd.zip
        
        /usr/data/pellcorp/k1/curl -s -L "https://raw.githubusercontent.com/fluidd-core/fluidd-config/master/client.cfg" -o /usr/data/printer_data/config/fluidd.cfg || exit $?
        # we already define pause resume and virtual sd card in printer.cfg
        sed -i '/^\[pause_resume\]/,/^$/d' /usr/data/printer_data/config/fluidd.cfg || exit $?
        sed -i '/^\[virtual_sdcard\]/,/^$/d' /usr/data/printer_data/config/fluidd.cfg || exit $?
        sed -i '/^\[display_status\]/,/^$/d' /usr/data/printer_data/config/fluidd.cfg || exit $?

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

        # lets allow reinstalls
        if [ -d /usr/data/mainsail ]; then
            rm -rf /usr/data/mainsail
        fi
        mkdir -p /usr/data/mainsail 
        /usr/data/pellcorp/k1/curl -s -L "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o /usr/data/mainsail.zip || exit $?
        unzip -qd /usr/data/mainsail /usr/data/mainsail.zip || exit $?
        rm /usr/data/mainsail.zip

        /usr/data/pellcorp/k1/curl -s -L "https://github.com/mainsail-crew/mainsail-config/blob/master/client.cfg" -o /usr/data/printer_data/config/mainsail.cfg || exit $?
        # we already define pause resume, display_status and virtual sd card in printer.cfg
        sed -i '/^\[pause_resume\]/,/^$/d' /usr/data/printer_data/config/mainsail.cfg || exit $?
        sed -i '/^\[virtual_sdcard\]/,/^$/d' /usr/data/printer_data/config/mainsail.cfg || exit $?
        sed -i '/^\[display_status\]/,/^$/d' /usr/data/printer_data/config/mainsail.cfg || exit $?

        # mainsail macros will conflict with fluidd ones
        # sed -i '/\[include gcode_macro\.cfg\]/a \[include mainsail\.cfg\]' /usr/data/printer_data/config/printer.cfg || exit $?

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

        # lets allow reinstalls
        if [ -d /usr/data/klipper ]; then
            rm -rf /usr/data/klipper
        fi
        git clone https://github.com/pellcorp/klipper.git /usr/data/klipper || exit $?
        cd /usr/data/klipper

        # remove existing version of klipper, no need to back it up
        # can restore this with (thanks to Guilouz for pointing this out):
        # rm -rf /overlay/upper/usr/share/klipper
        # mount -o remount /
        if [ -d /usr/share/klipper ]; then
            rm -rf /usr/share/klipper
        fi
        ln -sf /usr/data/klipper /usr/share/

        cp /usr/data/pellcorp/k1/sensorless.cfg /usr/data/printer_data/config/
        cp /usr/data/pellcorp/k1/S55klipper_service /etc/init.d/
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        sed -i '/^\[bl24c16f\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[mcu leveling_mcu\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[prtouch_v2\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^square_corner_max_velocity: 200.0$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^max_accel_to_decel.*/d' /usr/data/printer_data/config/printer.cfg || exit $?

        # proper fan control
        cp /usr/data/pellcorp/k1/fan_control.cfg /usr/data/printer_data/config
        sed -i '/\[include gcode_macro\.cfg\]/a \[include fan_control\.cfg\]' /usr/data/printer_data/config/printer.cfg
        
        sed -i '/^\[filament_switch_sensor filament_sensor_2\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[output_pin fan0\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[output_pin fan1\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[output_pin fan2\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?

        sed -i '/^\[include printer_params\.cfg\]$/d' /usr/data/printer_data/config/printer.cfg || exit $?

        # replace existing creality gcode_macro.cfg with our own saves having to remove from printer.cfg
        cp /usr/data/pellcorp/k1/custom_gcode.cfg /usr/data/printer_data/config/gcode_macro.cfg

        echo "klipper" >> /usr/data/pellcorp.done
        echo "WARNING: A power cycle is required to properly activate klipper!"
        sync
    fi
}

# guppy screen handles being reinstalled so just let it do its thing
install_guppyscreen() {
    grep "guppyscreen" /usr/data/pellcorp.done > /dev/null
    if [ $? -ne 0 ]; then
        echo ""
        echo "Installing guppyscreen ..."
        
        # this is mostly for k1-qemu where moonraker takes a while to start up
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

git config --global http.sslVerify false
# honestly not sure this helps
git config --global http.postBuffer 100000000

backup_config
disable_creality_services
install_moonraker
install_nginx
install_fluidd
install_mainsail

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

echo ""
echo "Please power cycle your printer to activate updated klipper and perform any nozzle firmware update!"
exit 0
