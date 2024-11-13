#!/bin/bash

# shamelessly stolen from https://github.com/Guilouz/Creality-Helper-Script/blob/main/scripts/custom_boot_display.sh
rm -rf /etc/boot-display/part0
cp /usr/data/pellcorp/k1/boot-display.conf /etc/boot-display/
cp /usr/data/pellcorp/k1/services/S11jpeg_display_shell /etc/init.d/
mkdir -p /usr/data/boot-display
tar -zxf "/usr/data/pellcorp/k1/boot-display.tar.gz" -C /usr/data/boot-display
ln -s /usr/data/boot-display/part0 /etc/boot-display/
sync
