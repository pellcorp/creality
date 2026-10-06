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

info=$(v4l2-ctl -d $device -l | grep "^[[:space:]]*$control " | head -1)
if [ -z "$info" ]; then
  echo "ERROR: Invalid control $control"
  exit 1
fi

save_value=$value
if [ "$value" = "default" ]; then
  value=$(echo "$info" | sed -n 's/.*default=\([-0-9]*\).*/\1/p')
fi

case "$value" in
  ''|-|*[!0-9-]*|?*-*)
    echo "ERROR: Invalid value $value for $control"
    exit 1
    ;;
esac

if echo "$info" | grep -q "(bool)" && [ "$value" != "0" ] && [ "$value" != "1" ]; then
  echo "ERROR: Value $value for $control must be 0 or 1"
  exit 1
fi

min=$(echo "$info" | sed -n 's/.*min=\([-0-9]*\).*/\1/p')
max=$(echo "$info" | sed -n 's/.*max=\([-0-9]*\).*/\1/p')
if [ -n "$min" ] && [ "$value" -lt "$min" ]; then
  echo "ERROR: Value $value for $control is below the minimum of $min"
  exit 1
fi
if [ -n "$max" ] && [ "$value" -gt "$max" ]; then
  echo "ERROR: Value $value for $control is above the maximum of $max"
  exit 1
fi

v4l2-ctl -d $device --set-ctrl $control=$value || exit 1
echo "INFO: Set $control to $value"

# remember the control so S50webcam can re-apply it on startup, a default value is forgotten
# an existing control is updated in place so dependent controls (eg auto off before a manual value) stay in order
CONFIG_HELPER="/usr/data/pellcorp/tools/config-helper.py"
if [ -f /usr/data/printer_data/config/camera.cfg ]; then
  saved=$($CONFIG_HELPER --file camera.cfg --get-section-entry "gcode_macro _CAMERA_CONTROL_SAVED" "variable_controls" | tr -d "'")
  [ "$saved" = "none" ] && saved=
  if [ "$save_value" = "default" ]; then
    saved=$(echo "$saved" | tr ',' '\n' | grep -v "^${control}=" | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
  elif echo ",$saved," | grep -q ",${control}="; then
    saved=$(echo "$saved" | tr ',' '\n' | sed "s/^${control}=.*/${control}=${value}/" | tr '\n' ',' | sed 's/,$//')
  else
    saved="${saved:+$saved,}$control=$value"
  fi
  [ -z "$saved" ] && saved=none
  $CONFIG_HELPER --file camera.cfg --replace-section-entry "gcode_macro _CAMERA_CONTROL_SAVED" "variable_controls" "'$saved'" || exit $?
fi
