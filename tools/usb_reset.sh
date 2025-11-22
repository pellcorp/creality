#!/bin/sh

device=$1

# thanks to Chad (aka ChatGPT) for this code
# https://chatgpt.com/share/68a844e5-f164-800d-808f-9ab18f40f1e1
reset_device() {
  local DEV=$1
  local TTY=$(readlink -f "$DEV") || exit 1
  local BASENAME=$(basename "$TTY")
  local SYSFS=$(readlink -f /sys/class/tty/$BASENAME/device)
  local IFACE=$(basename "$SYSFS")
  local DRIVER=$(basename "$(readlink -f "$SYSFS/driver")")

  echo "$IFACE" | sudo tee "/sys/bus/usb/drivers/$DRIVER/unbind" > /dev/null
  sleep 3
  echo "$IFACE" | sudo tee "/sys/bus/usb/drivers/$DRIVER/bind" > /dev/null
}

if [ "$device" = "cartographer" ]; then
  SERIAL_ID=$(ls /dev/serial/by-id/usb-* | grep "IDM\|Cartographer" | head -1)
elif [ "$device" = "eddy" ]; then
  SERIAL_ID=$(ls /dev/serial/by-id/usb-Klipper_rp2040* | head -1)
elif [ "$device" = "beacon" ]; then
  SERIAL_ID=$(ls /dev/serial/by-id/usb-Beacon_Beacon* | head -1)
fi

if [ -n "$SERIAL_ID" ]; then
  reset_device $SERIAL_ID
else
  echo "Failed to find $device!"
fi
exit 0
