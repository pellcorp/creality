#!/bin/sh

SCRIPT=$HOME/pellcorp/rpi/change-theme.sh
if grep -Fqs "ID=buildroot" /etc/os-release; then
    SCRIPT=/usr/data/pellcorp/k1/change-theme.sh
fi

$SCRIPT $@
