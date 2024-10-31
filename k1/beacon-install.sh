#!/bin/bash

KDIR="/usr/data/klipper"
BKDIR="/usr/data/beacon-klipper"

echo "Beacon: linking modules into klipper"
for file in beacon.py; do
    if [ -e "${KDIR}/klippy/extras/${file}" ]; then
        rm "${KDIR}/klippy/extras/${file}"
    fi
    ln -s "${BKDIR}/${file}" "${KDIR}/klippy/extras/${file}"
    if ! grep -q "klippy/extras/${file}" "${KDIR}/.git/info/exclude"; then
        echo "klippy/extras/${file}" >> "${KDIR}/.git/info/exclude"
    fi
done
