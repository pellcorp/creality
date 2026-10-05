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

if [ "$value" = "default" ]; then
  value=$(v4l2-ctl -d $device -l | grep "^[[:space:]]*$control " | sed -n 's/.*default=\([-0-9]*\).*/\1/p')
  if [ -z "$value" ]; then
    echo "ERROR: Invalid control $control"
    exit 1
  fi
fi

v4l2-ctl -d $device --set-ctrl $control=$value || exit 1
echo "INFO: Set $control to $value"
