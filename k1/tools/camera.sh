#!/bin/sh

device=$1

ID_FILE="/usr/data/tmp/camera_usb_id"

disconnect_camera() {
  local DEV=$(v4l2-ctl --list-devices|grep -A1 usb|sed 's/^[[:space:]]*//g'|grep '^/dev' | head -1)
  if [ -n "$DEV" ]; then
    local BASENAME=$(basename "$DEV")
    local SYSFS=$(readlink -f /sys/class/video4linux/$BASENAME/device)
    local IFACE=$(basename "$SYSFS")
    echo "$IFACE" > "$ID_FILE"
    echo "$IFACE" > "/sys/bus/usb/drivers/uvcvideo/unbind"
  fi
}

reconnect_camera() {
  if [ -f "$ID_FILE" ]; then
    local IFACE=$(cat "$ID_FILE")
    echo "$IFACE" > "/sys/bus/usb/drivers/uvcvideo/bind"
  fi
}

CURRENT_SERVICE_TYPE=$(cat /etc/init.d/S50webcam | grep SERVICE_TYPE= | awk -F '=' '{print $2}')
if [ "$CURRENT_SERVICE_TYPE" = "ustreamer" ]; then
  if [ "$1" = "--disconnect" ]; then
    disconnect_camera
  elif [ "$1" = "--connect" ]; then
    reconnect_camera
  fi
else # else if not ustreamer just stop and start like normal
  if [ "$1" = "--disconnect" ]; then
    /etc/init.d/S50webcam stop
  elif [ "$1" = "--connect" ]; then
    /etc/init.d/S50webcam start
  fi
fi
