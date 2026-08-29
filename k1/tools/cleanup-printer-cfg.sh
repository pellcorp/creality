#!/bin/sh

if [ -z "$BASEDIR" ]; then
  BASEDIR=/usr/data/pellcorp
fi

CONFIG_HELPER="$BASEDIR/tools/config-helper.py"

if [ -z "$MODEL" ]; then
  MODEL=$(/usr/bin/get_sn_mac.sh model)
fi

if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ] || [ "$MODEL" = "K1 SE" ]; then
  model=k1
elif [ "$MODEL" = "CR-K1 Max" ]; then
  model=k1m
elif [ "$MODEL" = "F001" ] || [ "$MODEL" = "F002" ]; then
  model=f001
elif [ "$MODEL" = "F004" ]; then
  model=f004
elif [ "$MODEL" = "F003" ]; then
  model=f003
elif [ "$MODEL" = "F005" ]; then
  model=f005
else
  echo "FATAL: Unsupported model $MODEL"
  exit 1
fi

if [ ! -f "$1" ]; then
  echo "FATAL: Invalid printer.cfg specified: $1"
  exit 1
fi

PRINTER_CFG=$1

# install_klipper will restore it where its required
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "mcu rpi" || exit $?

# just make sure the baud is written
$CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "mcu" "baud" 230400 || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "mcu nozzle_mcu" "baud" 230400 || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "mcu leveling_mcu" "baud" 230400 || exit $?

if [ "$MODEL" = "F004" ]; then
  # new versions of Ender 5 Max firmware added accel_chip_proxy to replace adxl
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "accel_chip_proxy" || exit $?

  $CONFIG_HELPER --file $PRINTER_CFG --add-section "adxl345"
  $CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "adxl345" "cs_pin" "nozzle_mcu:PA4" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "adxl345" "axes_map" "x,-z,y" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "adxl345" "spi_speed" "5000000" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "adxl345" "spi_software_sclk_pin" "nozzle_mcu:PA5" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "adxl345" "spi_software_mosi_pin" "nozzle_mcu:PA7" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "adxl345" "spi_software_miso_pin" "nozzle_mcu:PA6" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --replace-section-entry "resonance_tester" "accel_chip" "adxl345" || exit $?
fi

$CONFIG_HELPER --file $PRINTER_CFG --remove-section "Height_module2" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin aobi" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin USB_EN" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "hx711s" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "filter" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "dirzctl" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "accel_chip_proxy" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "z_compensate" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "soft_homing" || exit $?

$CONFIG_HELPER --file $PRINTER_CFG --remove-section "bl24c16f" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "prtouch_v2" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin power" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section-entry "printer" "square_corner_max_velocity" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section-entry "printer" "max_accel_to_decel" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section-entry "stepper_y" "gcode_position_max" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section-entry "stepper_x" "gcode_position_max" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "filament_switch_sensor filament_sensor_2" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section-entry "filament_switch_sensor filament_sensor" "runout_gcode" || exit $?

# https://www.klipper3d.org/TMC_Drivers.html#prefer-to-not-specify-a-hold_current
$CONFIG_HELPER --file $PRINTER_CFG --remove-section-entry "tmc2209 stepper_x" "hold_current" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section-entry "tmc2209 stepper_y" "hold_current" || exit $?

$CONFIG_HELPER --file $PRINTER_CFG --remove-include "sensorless.cfg" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-include "printer_params.cfg" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-include "gcode_macro.cfg" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-include "custom_gcode.cfg" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-include "box.cfg" || exit $?

if [ "$MODEL" = "F004" ]; then
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin MainBoardFan" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin en_nozzle_fan" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin en_fan0" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin en_fan1" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin col_pwm" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin col" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "heater_fan nozzle_fan" || exit $?
elif [ "$MODEL" = "F003" ] || [ "$MODEL" = "F005" ]; then
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin MainBoardFan" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "heater_fan nozzle_fan" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section "bltouch" || exit $?
  $CONFIG_HELPER --file $PRINTER_CFG --remove-section-entry "heater_bed" "temp_offset_flag" || exit $?
fi

$CONFIG_HELPER --file $PRINTER_CFG --remove-section "bed_mesh" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "input_shaper" || exit $?

$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin fan0" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin fan1" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin fan2" || exit $?

# a few strange duplicate pins appear in some firmware
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin PA0" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin PB2" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin PB10" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin PC8" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin PC9" || exit $?

$CONFIG_HELPER --file $PRINTER_CFG --remove-section "duplicate_pin_override" || exit $?

$CONFIG_HELPER --file $PRINTER_CFG --remove-section "static_digital_output my_fan_output_pins" || exit $?

# encountered an as yet unseen config from firmware
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "output_pin my_fan_output_pins" || exit $?

$CONFIG_HELPER --file $PRINTER_CFG --remove-section "heater_fan hotend_fan" || exit $?

# all the fans and temp sensors are going to fan control now
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "temperature_sensor mcu_temp" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "temperature_sensor chamber_temp" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "temperature_fan chamber_fan" || exit $?

# just in case anyone manually has added this to printer.cfg
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "temperature_fan mcu_fan" || exit $?

# the nozzle should not trigger the MCU anymore
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "multi_pin heater_fans" || exit $?

# moving idle timeout to start_end.cfg so we can have some integration with
# start and end print and warp stabilisation if needed
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "idle_timeout" || exit $?

# exclude object is defined in start_end.cfg
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "exclude_object" || exit $?

# these are defined in client.cfg
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "pause_resume" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "display_status" || exit $?
$CONFIG_HELPER --file $PRINTER_CFG --remove-section "virtual_sdcard" || exit $?

# apply various Ender 3 V3 patches to printer.cfg last thing
if [ "$MODEL" = "F002" ] || [ "$MODEL" = "F001" ]; then
  $CONFIG_HELPER --file $PRINTER_CFG --quiet --patches $BASEDIR/k1/patches/printer.cfg.f001 || exit $?
fi

if [ -f $BASEDIR/pellcorp/k1/patches/fan_control.${model}.cfg ]; then
  $CONFIG_HELPER --file $PRINTER_CFG --quiet --patches $BASEDIR/k1/patches/fan_control.${model}.cfg || exit $?
elif [ "$MODEL" = "K1 SE" ]; then
  $CONFIG_HELPER --file $PRINTER_CFG --quiet --patches $BASEDIR/k1/patches/fan_control.k1se.cfg || exit $?
else
  $CONFIG_HELPER --file $PRINTER_CFG --quiet --patches $BASEDIR/k1/patches/fan_control.cfg || exit $?
fi

# replace = with :
sed -i 's/ = /: /g' $PRINTER_CFG

# stamp the base factory printer so we know we have done the cleaning
sed -i "1s/^/# Simple AF Base Printer ($MODEL)\n/" $PRINTER_CFG
