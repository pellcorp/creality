#!/bin/sh

device=$1

# thanks to Chad (aka ChatGPT) for this code
# https://chatgpt.com/share/68a844e5-f164-800d-808f-9ab18f40f1e1
function reset_device() {
  local DEV=$1
  local TTY=$(readlink -f "$DEV") || exit 1
  local BASENAME=$(basename "$TTY")
  local SYSFS=$(readlink -f /sys/class/tty/$BASENAME/device)
  local IFACE=$(basename "$SYSFS")
  local DRIVER=$(basename "$(readlink -f "$SYSFS/driver")")

  echo "$IFACE" > "/sys/bus/usb/drivers/$DRIVER/unbind"
  sleep 3
  echo "$IFACE" > "/sys/bus/usb/drivers/$DRIVER/bind"
}

if [ "$device" = "scanner" ]; then
  SERIAL_ID=$(ls /dev/serial/by-id/usb-* | grep "IDM\|Cartographer" | head -1)
elif [ "$device" = "eddy" ]; then
  SERIAL_ID=$(ls /dev/serial/by-id/usb-Klipper_rp2040* | head -1)
fi

if [ -n "$SERIAL_ID" ]; then
  reset_device $SERIAL_ID
fi
exit 0
