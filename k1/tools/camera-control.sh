#!/bin/sh

control=
value=
for arg in "$@"; do
  case "$arg" in
    CONTROL=*) control=${arg#CONTROL=} ;;
    VALUE=*) value=${arg#VALUE=} ;;
  esac
done

device=$(v4l2-ctl --list-devices | grep -A1 usb | sed 's/^[[:space:]]*//g' | grep '^/dev' | head -1)
if [ -z "$device" ]; then
  echo "ERROR: No webcams found!"
  exit 1
fi

# no control just list the available controls and their current values
if [ -z "$control" ]; then
  v4l2-ctl -d $device -l
  exit $?
fi

if [ -z "$value" ]; then
  echo "ERROR: VALUE must be specified for CONTROL=$control"
  exit 1
fi

save_value=$value
if [ "$value" = "default" ]; then
  value=$(v4l2-ctl -d $device -l | grep "^[[:space:]]*$control " | sed -n 's/.*default=\([-0-9]*\).*/\1/p')
  if [ -z "$value" ]; then
    echo "ERROR: Invalid control $control"
    exit 1
  fi
fi

v4l2-ctl -d $device --set-ctrl $control=$value || exit 1
echo "INFO: Set $control to $value"

# remember the control so S50webcam can re-apply it on startup, a default value is forgotten
CONFIG_HELPER="/usr/data/pellcorp/tools/config-helper.py"
if [ -f /usr/data/printer_data/config/camera.cfg ]; then
  saved=$($CONFIG_HELPER --file camera.cfg --get-section-entry "gcode_macro _CAMERA_CONTROL_SAVED" "variable_controls" | tr -d "'")
  [ "$saved" = "none" ] && saved=
  saved=$(echo "$saved" | tr ',' '\n' | grep -v "^${control}=" | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
  if [ "$save_value" != "default" ]; then
    saved=$(echo "${saved:+$saved,}$control=$value")
  fi
  [ -z "$saved" ] && saved=none
  $CONFIG_HELPER --file camera.cfg --replace-section-entry "gcode_macro _CAMERA_CONTROL_SAVED" "variable_controls" "'$saved'" || exit $?
fi
