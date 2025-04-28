#!/bin/bash

BASEDIR=$HOME
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
mode=$1
probe=$2

grep -q "klipper" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
    if [ "$mode" != "update" ] && [ -d $BASEDIR/klipper ]; then
        sudo systemctl stop klipper-mcu 2> /dev/null
        sudo systemctl stop klipper 2> /dev/null
        # force rebuild of klipper-mcu
        [ -f /usr/local/bin/klipper_mcu ] && sudo rm /usr/local/bin/klipper_mcu
        rm -rf $BASEDIR/klipper
    fi

    if [ "$mode" != "update" ] && [ -d $BASEDIR/klippy-env ]; then
        rm -rf $BASEDIR/klippy-env
    fi

    if [ ! -d $BASEDIR/klipper/ ]; then
        echo "INFO: Installing klipper ..."

        git clone https://github.com/pellcorp/klipper-rpi.git $BASEDIR/klipper || exit $?
        $BASEDIR/klipper/scripts/install-ubuntu-22.04.sh || exit $?

        sudo systemctl stop klipper
        # the service file the installer generates is not sufficient lets override it
        sudo cp $BASEDIR/pellcorp/rpi/services/klipper.service /etc/systemd/system || exit $?
        sudo sed -i "s:\$HOME:$BASEDIR:g" /etc/systemd/system/klipper.service
        sudo sed -i "s:User=pi:User=$USER:g" /etc/systemd/system/klipper.service
        sudo systemctl daemon-reload

        # additional packages for things like eddyng, cartographer, beacon, etc
        sudo apt-get install --yes jq python3-numpy libopenblas-dev || exit $?
        $BASEDIR/klippy-env/bin/pip install numpy==1.26.2 || exit $?

        sudo usermod -a -G tty $USER
        sudo usermod -a -G dialout $USER
    fi

    if [ ! -d $BASEDIR/fluidd-config ]; then
        echo
        echo "INFO: Installing client macros ..."
        git clone https://github.com/fluidd-core/fluidd-config.git $BASEDIR/fluidd-config || exit $?
    fi

    ln -sf $BASEDIR/fluidd-config/client.cfg $BASEDIR/printer_data/config/
    $CONFIG_HELPER --add-include "client.cfg" || exit $?

    kinematics=$($CONFIG_HELPER --get-section-entry "printer" "kinematics")
    if [ "$kinematics" = "corexy" ]; then
        if [ ! -d $BASEDIR/klippain_shaketune ]; then
            echo "INFO: Installing Klippain ShakeTune ..."
            command -v wget 2> /dev/null
            if [ $? -ne 0 ]; then
                sudo apt-get install --yes wget || exit $?
            fi
            wget -O - https://raw.githubusercontent.com/Frix-x/klippain-shaketune/main/install.sh | bash
        fi
    fi

    cp $BASEDIR/pellcorp/config/sensorless.cfg $BASEDIR/printer_data/config/ || exit $?
    $CONFIG_HELPER --add-include "sensorless.cfg" || exit $?

    cp $BASEDIR/pellcorp/rpi/internal_macros.cfg $BASEDIR/printer_data/config/ || exit $?
    sudo sed -i "s:\$HOME:$BASEDIR:g" $BASEDIR/printer_data/config/internal_macros.cfg
    $CONFIG_HELPER --add-include "internal_macros.cfg" || exit $?

    cp $BASEDIR/pellcorp/config/useful_macros.cfg $BASEDIR/printer_data/config/ || exit $?
    $CONFIG_HELPER --add-include "useful_macros.cfg" || exit $?

    cp $BASEDIR/pellcorp/config/start_end.cfg $BASEDIR/printer_data/config/ || exit $?
    $CONFIG_HELPER --add-include "start_end.cfg" || exit $?

    if [ "$kinematics" = "cartesian" ]; then
        # for cartesian no cool down necessary
        $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _START_END_PARAMS" "variable_end_print_cool_down" "False" || exit $?
    fi

    ln -sf $BASEDIR/pellcorp/config/Line_Purge.cfg $BASEDIR/printer_data/config/ || exit $?
    $CONFIG_HELPER --add-include "Line_Purge.cfg" || exit $?

    ln -sf $BASEDIR/pellcorp/config/Smart_Park.cfg $BASEDIR/printer_data/config/ || exit $?
    $CONFIG_HELPER --add-include "Smart_Park.cfg" || exit $?

    cp $BASEDIR/pellcorp/rpi/fan_control.cfg $BASEDIR/printer_data/config || exit $?
    $CONFIG_HELPER --add-include "fan_control.cfg" || exit $?

    # replace a [fan] with a part fan
    pin=$($CONFIG_HELPER --get-section-entry "fan" "pin")
    if [ -n "$pin" ]; then
        $CONFIG_HELPER --remove-section "fan" || exit $?
        $CONFIG_HELPER --add-section "fan_generic part" || exit $?
        $CONFIG_HELPER --replace-section-entry "fan_generic part" "pin" "$pin" || exit $?
        $CONFIG_HELPER --replace-section-entry "fan_generic part" "cycle_time" "0.0100" || exit $?
        $CONFIG_HELPER --replace-section-entry "fan_generic part" "hardware_pwm" "false" || exit $?
    fi

    if [ "$kinematics" = "corexy" ]; then
        cp $BASEDIR/pellcorp/rpi/klippain.cfg $BASEDIR/printer_data/config || exit $?
        if $CONFIG_HELPER --section-exists "resonance_tester"; then
            $CONFIG_HELPER --add-include "klippain.cfg" || exit $?
        else
            echo "INFO: SKipped including klippain.cfg as no resonance_tester"
        fi
    fi

    # just in case its missing from stock printer.cfg make sure it gets added
    $CONFIG_HELPER --add-section "exclude_object" || exit $?

    if [ ! -f /usr/local/bin/klipper_mcu ]; then
        echo "INFO: Setting up Klipper MCU ..."
        cd $BASEDIR/klipper
        cp .config.linux .config
        make clean
        make || exit $?
        sudo cp out/klipper.elf /usr/local/bin/klipper_mcu || exit $?
        sudo cp ./scripts/klipper-mcu.service /etc/systemd/system/ || exit $?
        sudo systemctl enable klipper-mcu || exit $?
        sudo systemctl start klipper-mcu || exit $?
    fi

    # add klipper mcu
    $CONFIG_HELPER --add-section "mcu rpi" || exit $?
    $CONFIG_HELPER --replace-section-entry "mcu rpi" "serial" "/tmp/klipper_host_mcu" || exit $?

    if $CONFIG_HELPER --section-exists "filament_switch_sensor filament_sensor"; then
        $CONFIG_HELPER --replace-section-entry "filament_switch_sensor filament_sensor" "runout_gcode" "_ON_FILAMENT_RUNOUT" || exit $?
    else
        echo
        echo "WARN: No filament sensor configured skipping on filament runout configuration"
    fi

    echo "klipper" >> $BASEDIR/pellcorp.done
fi
