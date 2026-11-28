#!/bin/bash

disconnect_device() {
  local BASE_SERIAL_ID=$1
  local TTY=$(readlink -f "/dev/serial/by-id/${SERIAL_ID}") || exit 1
  local BASENAME=$(basename "$TTY")
  local SYSFS=$(readlink -f /sys/class/tty/$BASENAME/device)
  local IFACE=$(basename "$SYSFS")
  local DRIVER=$(basename "$(readlink -f "$SYSFS/driver")")
  echo "sysfs=$SYSFS" > "/tmp/${BASE_SERIAL_ID}.sysfs"
  echo "driver=$DRIVER" >> "/tmp/${BASE_SERIAL_ID}.sysfs"
  echo "$IFACE" | sudo tee "/sys/bus/usb/drivers/$DRIVER/unbind" > /dev/null
}

connect_device() {
    local BASE_SERIAL_ID=$1
    local SYSFS=$(cat "/tmp/${BASE_SERIAL_ID}.sysfs" | grep "sysfs=" | awk -F '=' '{print $2}')
    local DRIVER=$(cat "/tmp/${BASE_SERIAL_ID}.sysfs" | grep "driver=" | awk -F '=' '{print $2}')
    local IFACE=$(basename "$SYSFS")
    echo "$IFACE" | sudo tee "/sys/bus/usb/drivers/$DRIVER/bind" > /dev/null
}

MODE="$1"
SERIAL_ID="$2"

if [ -n "$SERIAL_ID" ] && [ "$MODE" = "--unbind" ]; then
  if [ -e "${SERIAL_ID}" ]; then
    BASE_SERIAL_ID=$(basename $SERIAL_ID)
    disconnect_device "$BASE_SERIAL_ID"
    exit 0
  else
    echo "ERROR: Serial device not present"
    exit 1
  fi
elif [ -n "$SERIAL_ID" ] && [ "$MODE" = "--bind" ]; then
  BASE_SERIAL_ID=$(basename $SERIAL_ID)
  if [ -e "${SERIAL_ID}" ]; then
    echo "ERROR: Device is already bound"
    exit 1
  elif [ -f /tmp/${BASE_SERIAL_ID}.sysfs ]; then
    connect_device "$BASE_SERIAL_ID"
    exit 0
  else
    echo "ERROR: Serial device is not present and was not previously unbound"
    exit 1
  fi
else
  echo "Usage: $(basename $0) <[--unbind|--bind]> <SERIAL_ID>"
  exit 1
fi
