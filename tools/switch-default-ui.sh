#!/bin/sh

SCRIPT=$HOME/pellcorp/rpi/switch-default-ui.sh
if grep -Fqs "ID=buildroot" /etc/os-release; then
    SCRIPT=/usr/data/pellcorp/k1/switch-default-ui.sh
fi

$SCRIPT $@
