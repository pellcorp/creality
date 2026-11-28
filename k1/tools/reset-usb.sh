#!/bin/sh
# Creality K1: reinitialize the USB controller and all devices attached to it.
# Run as root while the printer is idle. Camera/Klipper recovery is manual.
set -eu

driver=/sys/bus/platform/drivers/dwc2
device=13500000.otg_new

# Reattach the controller if the script is interrupted after detaching it.
reattach() {
    if [ ! -e "$driver/$device" ]; then
        printf '%s' "$device" > "$driver/bind"
    fi
}
trap reattach 0
trap 'exit 1' 1 2 15

printf '%s' "$device" > "$driver/unbind"
sleep 3
printf '%s' "$device" > "$driver/bind"
trap - 0 1 2 15
sleep 5

echo "USB controller reset complete."
