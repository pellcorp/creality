#!/bin/sh

if [ ! -f /usr/data/printer_data/config/printer.cfg ]; then
  >&2 echo "ERROR: Printer data not setup"
  exit 1
fi

# https://stackoverflow.com/a/1638397
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

if [ "$SCRIPTPATH" != "/usr/data/pellcorp/k1" ]; then
  >&2 echo "ERROR: This git repo must be cloned to /usr/data/pellcorp"
fi

if [ ! -f /etc/init.d/S51factoryreset ]; then
    echo "The emergency factory reset 'service' is not present - aborting"
    exit 1
fi

install_moonraker() {
    grep "moonraker" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Installing moonraker ..."
        git clone https://github.com/Arksine/moonraker /usr/data/moonraker || exit $?
        cp /usr/data/pellcorp/k1/S56moonraker_service /etc/init.d/
        cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/
        cp /usr/data/pellcorp/k1/notifier.conf /usr/data/printer_data/config/
        cp /usr/data/pellcorp/k1/moonraker.secrets /usr/data/printer_data/
        tar -zxf /usr/data/pellcorp/k1/moonraker-env.tar.gz -C /usr/data/
        echo "moonraker" >> /usr/data/pellcorp.cfg
        sync
    fi
}

install_nginx() {
    grep "nginx" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Installing nginx ..."
        tar -zxf /usr/data/pellcorp/k1/nginx.tar.gz -C /usr/data/ || exit $?
        cp /usr/data/pellcorp/k1/nginx.conf /usr/data/nginx/nginx/
        cp /usr/data/pellcorp/k1/S50nginx_service /etc/init.d/
        echo "nginx" >> /usr/data/pellcorp.cfg
        sync
    fi
}

disable_creality_services() {
    grep "creality" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Disabling some creality services ..."
        echo "IMPORTANT: If you reboot the printer before installing guppyscreen, the screen will be blank - this is to be expected!"
        mkdir -p /usr/data/backup
        /etc/init.d/S99start_app stop
        mv /etc/init.d/S99start_app /usr/data/backup
        mv /etc/init.d/S70cx_ai_middleware /usr/data/backup/
        mv /etc/init.d/S97webrtc /usr/data/backup/
        mv /etc/init.d/S99mdns /usr/data/backup/
        echo "creality" >> /usr/data/pellcorp.cfg
        sync
    fi
}

install_fluidd() {
    grep "fluidd" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Installing fluidd ..."
        mkdir -p /usr/data/fluidd 
        /usr/data/pellcorp/k1/curl -s -L "https://github.com/fluidd-core/fluidd/releases/download/v1.30.0/fluidd.zip" -o /usr/data/fluidd.zip || exit $?
        unzip -qd /usr/data/fluidd /usr/data/fluidd.zip
        rm /usr/data/fluidd.zip

        git clone https://github.com/fluidd-core/fluidd-config.git /usr/data/fluidd-config || exit $?
        ln -sf /usr/data/fluidd-config/fluidd.cfg /usr/data/printer_data/config/fluidd.cfg
        sed -i '/\[include gcode_macro\.cfg\]/a \[include fluidd\.cfg\]' /usr/data/printer_data/config/printer.cfg || exit $?
        echo "fluidd" >> /usr/data/pellcorp.cfg
        sync
    fi
}

start_moonraker_nginx() {
    /etc/init.d/S56moonraker_service start
    /etc/init.d/S50nginx_service start
}

install_klipper() {
    grep "klipper" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Installing klipper ..."
        mkdir -p /usr/data/backup
        git clone https://github.com/pellcorp/klipper.git /usr/data/klipper || exit $?
        cd /usr/data/klipper
        mv /usr/share/klipper /usr/data/backup/
        mv /usr/data/printer_data/config/sensorless.cfg /usr/data/backup/
        ln -s /usr/data/klipper /usr/share/
        cp /usr/data/pellcorp/k1/sensorless.cfg /usr/data/printer_data/config/
        mv /etc/init.d/S55klipper_service /usr/data/backup/
        cp /usr/data/pellcorp/k1/S55klipper_service /etc/init.d/
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy

        sed -i '/^\[bl24c16f\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[mcu leveling_mcu\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[prtouch_v2\]/,/^$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^square_corner_max_velocity: 200.0$/d' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[include gcode_macro\.cfg\]/#\[include gcode_macro\.cfg\]/g' /usr/data/printer_data/config/printer.cfg || exit $?
        sed -i '/^\[include printer_params\.cfg\]/#\[include printer_params\.cfg\]/g' /usr/data/printer_data/config/printer.cfg || exit $?
        echo "klipper" >> /usr/data/pellcorp.cfg
        sync
    fi
}

install_guppyscreen() {
    grep "guppyscreen" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Installing guppyscreen ..."
        /usr/data/pellcorp/k1/curl -s -L "https://raw.githubusercontent.com/ballaswag/guppyscreen/main/installer.sh" -o /usr/data/guppy-installer.sh || exit $?
        chmod 777 /usr/data/guppy-installer.sh
        /usr/data/guppy-installer.sh || exit $?
        rm /usr/data/guppy-installer.sh
        
        # guppyscreen installs some new python stuff so compile that stuff now
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy
        echo "guppyscreen" >> /usr/data/pellcorp.cfg
    fi
}

# generic probe stuff
setup_probe() {
    grep "probe" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Setting up generic probe config ..."
        sed -i '/^\[bed_mesh\]/,/^$/d' /usr/data/printer_data/config/printer.cfg
        sed -i '/\[include gcode_macro\.cfg\]/a \[include bltouch\.cfg\]' /usr/data/printer_data/config/printer.cfg
        sed -i 's/^endstop_pin: tmc2209_stepper_z:virtual_endstop.*/endstop_pin: probe:z_virtual_endstop/g' printer.cfg
        sed -i '/^position_endstop: 0/,/^$/d' /usr/data/printer_data/config/printer.cfg

        cp /usr/data/pellcorp/k1/fan_control.cfg /usr/data/printer_data/config
        sed -i '/\[include gcode_macro\.cfg\]/a \[include fan_control\.cfg\]' /usr/data/printer_data/config/printer.cfg
        
        cp /usr/data/pellcorp/k1/custom_gcode.cfg /usr/data/printer_data/config
        sed -i '/\[include gcode_macro\.cfg\]/a \[include custom_gcode\.cfg\]' /usr/data/printer_data/config/printer.cfg
        echo "probe" >> /usr/data/pellcorp.cfg
    fi
}

setup_bltouch() {
    grep "bltouch" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Setting up bltouch ..."
        cp /usr/data/pellcorp/k1/bltouch.cfg /usr/data/printer_data/config/
        sed -i '/\[include gcode_macro\.cfg\]/a \[include bltouch\.cfg\]' /usr/data/printer_data/config/printer.cfg
        echo "microprobe" >> /usr/data/pellcorp.cfg
    fi
}

setup_microprobe() {
    grep "microprobe" /usr/data/pellcorp.cfg > /dev/null
    if [ $? -ne 0 ]; then
        echo "Setting up microprobe ..."
        cp /usr/data/pellcorp/k1/microprobe.cfg /usr/data/printer_data/config/
        sed -i '/\[include gcode_macro\.cfg\]/a \[include microprobe\.cfg\]' /usr/data/printer_data/config/printer.cfg
        echo "microprobe" >> /usr/data/pellcorp.cfg
    fi
}

touch /usr/data/pellcorp.cfg

install_moonraker
install_nginx
disable_creality_services
install_fluidd
start_moonraker_nginx
install_klipper
install_guppyscreen
setup_probe
setup_microprobe
