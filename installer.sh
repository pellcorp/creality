#!/bin/sh

INSTALL_DIR=$HOME/pellcorp/rpi
if grep -Fqs "ID=buildroot" /etc/os-release; then
    INSTALL_DIR=/usr/data/pellcorp/k1
fi

$INSTALL_DIR/installer.sh $@
