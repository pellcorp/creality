#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
mode=$1
probe=$2

PYTHONDIR="${HOME}/klippy-env"
SYSTEMDDIR="/etc/systemd/system"
KLIPPER_USER=$USER
KLIPPER_GROUP=$KLIPPER_USER

# taken from https://github.com/pellcorp/klipper-rpi/blob/master/scripts/install-ubuntu-22.04.sh
function install_packages() {
  # Packages for python cffi
  PKGLIST="virtualenv python3-dev libffi-dev build-essential"
  # kconfig requirements
  PKGLIST="${PKGLIST} libncurses-dev"
  # hub-ctrl
  PKGLIST="${PKGLIST} libusb-dev"
  # AVR chip installation and building
  PKGLIST="${PKGLIST} avrdude gcc-avr binutils-avr avr-libc"
  # ARM chip installation and building
  PKGLIST="${PKGLIST} stm32flash dfu-util pkg-config libnewlib-arm-none-eabi"
  PKGLIST="${PKGLIST} gcc-arm-none-eabi binutils-arm-none-eabi libusb-1.0"

  # additional stuff for numpy for input shaping, cartographer, beacon, eddy-ng
  PKGLIST="${PKGLIST} python3-numpy python3-matplotlib libatlas-base-dev libopenblas-dev"

  retry sudo apt-get install --yes ${PKGLIST}; error
}

grep -q "klipper" $BASEDIR/pellcorp.done
if [ $? -ne 0 ]; then
  if [ "$mode" != "update" ] && [ -d $BASEDIR/klipper ]; then
    sudo systemctl stop klipper-mcu 2> /dev/null
    sudo systemctl stop klipper 2> /dev/null
    # force rebuild of klipper-mcu
    [ -f /usr/local/bin/klipper_mcu ] && sudo rm /usr/local/bin/klipper_mcu
    rm -rf $BASEDIR/klipper
  fi

  if [ -d $BASEDIR/klipper ]; then
    cd $BASEDIR/klipper
    git log | grep -q "support M106 P argument thanks to Chad"
    klipper_status=$?
    cd - > /dev/null

    if [ $klipper_status -ne 0 ]; then
      echo
      echo "INFO: Forcing update of klipper to latest master"
      rm -rf $BASEDIR/klipper
    fi
  fi

  if [ "$mode" != "update" ] && [ -d $BASEDIR/klippy-env ]; then
    rm -rf $BASEDIR/klippy-env
  fi

  if [ ! -d $BASEDIR/klipper/ ]; then
    echo
    echo "INFO: Installing klipper ..."

    git clone https://github.com/pellcorp/klipper-rpi.git $BASEDIR/klipper || exit $?
    install_packages

    if grep -q "dialout" /etc/group; then
      sudo usermod -a -G dialout $USER
    fi

    if grep -q "tty" /etc/group; then
      sudo usermod -a -G tty $USER
    fi

    # derived from https://github.com/dw-0/kiauh/blob/master/scripts/klipper.sh
    # https://klipper.discourse.group/t/other-single-board-computers-sbc-apart-from-raspberry-pis/6323
    if [[ $(dpkg -s brltty  2>/dev/null | grep "Status") = *\ installed ]]; then
      sudo systemctl stop brltty
      sudo systemctl mask brltty
    fi

    if [[ $(dpkg -s brltty-udev  2>/dev/null | grep "Status") = *\ installed ]]; then
      sudo systemctl stop brltty-udev
      sudo systemctl mask brltty-udev
    fi

    if [[ $(dpkg -s ModemManager  2>/dev/null | grep "Status") = *\ installed ]]; then
      sudo systemctl stop ModemManager
      sudo systemctl mask ModemManager
    fi
  fi

  # in case there are any updates to the klipper service need to rewrite
  sudo cp $BASEDIR/pellcorp/rpi/services/klipper.service /etc/systemd/system || exit $?
  sudo sed -i "s:\$HOME:$BASEDIR:g" /etc/systemd/system/klipper.service
  sudo sed -i "s:User=pi:User=$USER:g" /etc/systemd/system/klipper.service
  sudo systemctl enable klipper
  sudo systemctl daemon-reload

  if [ ! -d $BASEDIR/klippy-env ]; then
    virtualenv -p python3 $BASEDIR/klippy-env
    $BASEDIR/klippy-env/bin/pip install -r $BASEDIR/klipper/scripts/klippy-requirements.txt
    $BASEDIR/klippy-env/bin/pip install numpy==1.26.2 || exit $?
  fi

  echo "INFO: Updating klipper config ..."

  if [ ! -d $BASEDIR/fluidd-config ]; then
    git clone https://github.com/fluidd-core/fluidd-config.git $BASEDIR/fluidd-config || exit $?
  fi

  ln -sf $BASEDIR/fluidd-config/client.cfg $BASEDIR/printer_data/config/
  $CONFIG_HELPER --add-include "client.cfg" || exit $?

  kinematics=$($CONFIG_HELPER --get-section-entry "printer" "kinematics")
  if [ "$kinematics" = "corexy" ]; then
    # force reinstallation of klippain for anything other than an update
    if [ "$mode" != "update" ] && [ -d $BASEDIR/klippain_shaketune ]; then
      rm -rf $BASEDIR/klippain_shaketune
    fi

    if [ ! -d $BASEDIR/klippain_shaketune ]; then
      echo
      echo "INFO: Installing Klippain ShakeTune ..."
      command -v wget 2> /dev/null
      if [ $? -ne 0 ]; then
          retry sudo apt-get install --yes wget; error
      fi
      wget -O - https://raw.githubusercontent.com/Frix-x/klippain-shaketune/main/install.sh | bash
    fi
  fi

  cp $BASEDIR/pellcorp/config/sensorless.cfg $BASEDIR/printer_data/config/homing_override.cfg || exit $?
  $CONFIG_HELPER --add-include "homing_override.cfg" || exit $?

  x_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_max" --divisor 2 --integer)
  $CONFIG_HELPER --file homing_override.cfg --replace-section-entry "gcode_macro _SENSORLESS_PARAMS" "variable_home_x" "$x_position_mid" || exit $?

  y_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max" --divisor 2 --integer)
  $CONFIG_HELPER --file homing_override.cfg --replace-section-entry "gcode_macro _SENSORLESS_PARAMS" "variable_home_y" "$y_position_mid" || exit $?

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

  if [ "$probe" != "beacon" ] && [ "$probe" != "cartotouch" ] && [ "$probe" != "eddyng" ]; then
    $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _START_END_PARAMS" "variable_start_print_bed_heating_move_bed_distance" "0" || exit $?
  fi

  ln -sf $BASEDIR/pellcorp/config/Line_Purge.cfg $BASEDIR/printer_data/config/ || exit $?
  $CONFIG_HELPER --add-include "Line_Purge.cfg" || exit $?

  ln -sf $BASEDIR/pellcorp/config/Smart_Park.cfg $BASEDIR/printer_data/config/ || exit $?
  $CONFIG_HELPER --add-include "Smart_Park.cfg" || exit $?

  cp $BASEDIR/pellcorp/rpi/fan_control.cfg $BASEDIR/printer_data/config || exit $?
  $CONFIG_HELPER --add-include "fan_control.cfg" || exit $?

  # replace a [fan_generic part] with a [fan]
  pin=$($CONFIG_HELPER --get-section-entry "fan_generic part" "pin")
  if [ -n "$pin" ]; then
    $CONFIG_HELPER --remove-section "fan_generic part" || exit $?
    $CONFIG_HELPER --add-section "fan" || exit $?
    $CONFIG_HELPER --replace-section-entry "fan" "pin" "$pin" || exit $?
    $CONFIG_HELPER --replace-section-entry "fan" "cycle_time" "0.0100" || exit $?
    $CONFIG_HELPER --replace-section-entry "fan" "hardware_pwm" "false" || exit $?
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
    # https://klipper.discourse.group/t/armbian-kernel-klipper-host-mcu-got-error-1-in-sched-setschedule/1193
    runtime_us=$(sudo sysctl -n kernel.sched_rt_runtime_us)
    if [ "$runtime_us" != "-1" ]; then
      sudo sysctl -w kernel.sched_rt_runtime_us=-1 > /dev/null
      echo "kernel.sched_rt_runtime_us = -1" | sudo tee /etc/sysctl.d/10-disable-rt-group-limit.conf > /dev/null
    fi

    cd $BASEDIR/klipper
    cp .config.linux .config
    make clean
    make || exit $?
    rm .config
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
    # the _ON_FILAMENT_RUNOUT macro is going to be in control of filament runout now and avoid triggering another
    # runout event if already paused
    $CONFIG_HELPER --replace-section-entry "filament_switch_sensor filament_sensor" "pause_on_runout" "false" || exit $?
  else
    echo
    echo "WARN: No filament sensor configured skipping on filament runout configuration"
  fi

  echo "klipper" >> $BASEDIR/pellcorp.done
fi
