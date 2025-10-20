#!/bin/bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
RPI_DIR=$(dirname $CURRENT_DIR)
CREALITY_DIR=$(dirname $RPI_DIR)
ROOT_DIR=$(dirname $CREALITY_DIR)

CONFIG_DIR=$ROOT_DIR/Creality-K1-Extracted-Firmwares/Firmware/usr/share/klipper/config/

if [ ! -d $CONFIG_DIR ]; then
  echo "Missing $ROOT_DIR/Creality-K1-Extracted-Firmwares/Firmware/usr/share/klipper/config/"
  exit 1
fi

CONFIG_HELPER="$CREALITY_DIR/tools/config-helper.py"

function cleanup_printer_cfg() {
  local source=$1
  local target=$2
  local model=$3

  if [ ! -f $CONFIG_DIR/$source/printer.cfg ]; then
    echo "Failed to find $CONFIG_DIR/$source/printer.cfg"
    exit 1
  fi

  echo "Creating $target ..."
  cp $CONFIG_DIR/$source/printer.cfg $CREALITY_DIR/rpi/printers/$target || exit $?

  local file=$CREALITY_DIR/rpi/printers/$target

  # various crap from creality firmware
  $CONFIG_HELPER --file $file --remove-section "Height_module2" || exit $?
  $CONFIG_HELPER --file $file --remove-section "output_pin aobi" || exit $?
  $CONFIG_HELPER --file $file --remove-section "output_pin USB_EN" || exit $?
  $CONFIG_HELPER --file $file --remove-section "hx711s" || exit $?
  $CONFIG_HELPER --file $file --remove-section "filter" || exit $?
  $CONFIG_HELPER --file $file --remove-section "dirzctl" || exit $?
  $CONFIG_HELPER --file $file --remove-section "accel_chip_proxy" || exit $?
  $CONFIG_HELPER --file $file --remove-section "z_compensate" || exit $?
  $CONFIG_HELPER --file $file --remove-section "mcu leveling_mcu" || exit $?
  $CONFIG_HELPER --file $file --remove-section "bl24c16f" || exit $?
  $CONFIG_HELPER --file $file --remove-section "prtouch_v2" || exit $?
  $CONFIG_HELPER --file $file --remove-section "output_pin power" || exit $?

  # a few strange duplicate pins appear in some firmware
  $CONFIG_HELPER --file $file --remove-section "output_pin PA0" || exit $?
  $CONFIG_HELPER --file $file --remove-section "output_pin PB2" || exit $?
  $CONFIG_HELPER --file $file --remove-section "output_pin PB10" || exit $?
  $CONFIG_HELPER --file $file --remove-section "output_pin PC8" || exit $?
  $CONFIG_HELPER --file $file --remove-section "output_pin PC9" || exit $?

  # bed mesh will be in probe specific .cfg
  $CONFIG_HELPER --file $file --remove-section "bed_mesh" || exit $?

  # we will be defining mcu rpi separately
  $CONFIG_HELPER --file $file --remove-section "mcu rpi" || exit $?

  # update the pik1 serials
  $CONFIG_HELPER --file $file --replace-section-entry "mcu nozzle_mcu" "serial" "/dev/ttyGS1" || exit $?
  $CONFIG_HELPER --file $file --replace-section-entry "mcu" "serial" "/dev/ttyGS0" || exit $?

  # old klipper stuff
  $CONFIG_HELPER --file $file --remove-section-entry "printer" "square_corner_max_velocity" || exit $?
  $CONFIG_HELPER --file $file --remove-section-entry "printer" "max_accel_to_decel" || exit $?
  $CONFIG_HELPER --file $file --remove-section-entry "stepper_y" "gcode_position_max" || exit $?
  $CONFIG_HELPER --file $file --remove-section-entry "stepper_x" "gcode_position_max" || exit $?

  # https://www.klipper3d.org/TMC_Drivers.html#prefer-to-not-specify-a-hold_current
  $CONFIG_HELPER --file $file --remove-section-entry "tmc2209 stepper_x" "hold_current" || exit $?
  $CONFIG_HELPER --file $file --remove-section-entry "tmc2209 stepper_y" "hold_current" || exit $?

  # the creality firmware includes
  $CONFIG_HELPER --file $file --remove-include "printer_params.cfg" || exit $?
  $CONFIG_HELPER --file $file --remove-include "gcode_macro.cfg" || exit $?
  $CONFIG_HELPER --file $file --remove-include "custom_gcode.cfg" || exit $?
  $CONFIG_HELPER --file $file --remove-include "box.cfg" || exit $?
  $CONFIG_HELPER --file $file --remove-include "sensorless.cfg" || exit $?

  # weird arse hotend stuff config
  $CONFIG_HELPER --file $file --remove-section "static_digital_output my_fan_output_pins" || exit $?
  $CONFIG_HELPER --file $file --remove-section "multi_pin heater_fans" || exit $?

  if $CONFIG_HELPER --file $file --section-exists "heater_fan hotend_fan"; then
    $CONFIG_HELPER --file $file --remove-section "heater_fan hotend_fan" || exit $?
    $CONFIG_HELPER --file $file --add-section "heater_fan hotend" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "heater_fan hotend" "pin" "nozzle_mcu:PB5" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "heater_fan hotend" "tachometer_pin" "^nozzle_mcu:PB4" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "heater_fan hotend" "heater" "extruder" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "heater_fan hotend" "heater_temp" "40" || exit $?
  fi

  # this stuff will be provided by fluidd client macros
  $CONFIG_HELPER --file $file --remove-section "idle_timeout" || exit $?
  $CONFIG_HELPER --file $file --remove-section "exclude_object" || exit $?
  $CONFIG_HELPER --file $file --remove-section "pause_resume" || exit $?
  $CONFIG_HELPER --file $file --remove-section "display_status" || exit $?
  $CONFIG_HELPER --file $file --remove-section "virtual_sdcard" || exit $?

  part_pin=$($CONFIG_HELPER --file $file --get-section-entry "output_pin fan0" "pin")
  if [ -n "$part_pin" ]; then
    $CONFIG_HELPER --file $file --remove-section "output_pin fan0" || exit $?
    $CONFIG_HELPER --file $file --add-section "fan_generic part" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic part" "pin" "$part_pin" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic part" "cycle_time" "0.0100" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic part" "hardware_pwm" "false" || exit $?
  fi

  aux_pin=$($CONFIG_HELPER --file $file --get-section-entry "output_pin fan2" "pin")
  if [ -n "$aux_pin" ]; then
    $CONFIG_HELPER --file $file --remove-section "output_pin fan2" || exit $?
    $CONFIG_HELPER --file $file --add-section "fan_generic auxiliary" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic auxiliary" "pin" "$aux_pin" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic auxiliary" "cycle_time" "0.002" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic auxiliary" "hardware_pwm" "false" || exit $?
  fi

  chamber_pin=$($CONFIG_HELPER --file $file --get-section-entry "output_pin fan1" "pin")
  if [ -n "$chamber_pin" ]; then
    $CONFIG_HELPER --file $file --remove-section "output_pin fan1" || exit $?
    $CONFIG_HELPER --file $file --add-section "fan_generic chamber" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic chamber" "pin" "$chamber_pin" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic chamber" "cycle_time" "0.0100" || exit $?
    $CONFIG_HELPER --file $file --replace-section-entry "fan_generic chamber" "hardware_pwm" "false" || exit $?
  fi

  # in order to take advantage of the mounts for the various K1 series printers
  # we need to include a MODEL: header
  sed -i '/^#/d' $file
  sed -i "1i\# Creality $(basename $target .cfg) printer definition for https://rentry.co/k1-with-pi/" $file
  sed -i "2i\# MODEL:$model" $file
}

cleanup_printer_cfg K1_CR4CU220812S12 creality-k1-2023.cfg k1
cleanup_printer_cfg K1_CR4CU220812S12_1 creality-k1-2024.cfg k1
cleanup_printer_cfg K1_MAX_CR4CU220812S12 creality-k1m-2023.cfg k1m
cleanup_printer_cfg K1_MAX_CR4CU220812S12_1 creality-k1m-2024.cfg k1m
cleanup_printer_cfg K1C_CR4CU220812S12 creality-k1c.cfg k1
cleanup_printer_cfg K1_SE_CR4CU220812S12 creality-k1se.cfg k1
