#!/bin/bash

BASEDIR=$HOME

KDIR="${BASEDIR}/klipper"
KENV="${BASEDIR}/klippy-env"
BKDIR="${BASEDIR}/cartographer-klipper"

# we want to skip the matplotlib which triggers a long compile for no good reason
"${KENV}/bin/pip" install -r "$BASEDIR/pellcorp/rpi/cartotouch-requirements.txt"

# update link to scanner.py, cartographer.py & idm.py
echo "Cartographer: linking modules into klipper"
for file in idm.py cartographer.py scanner.py; do
    if [ -e "${KDIR}/klippy/extras/${file}" ]; then
        rm "${KDIR}/klippy/extras/${file}"
    fi
    ln -sf "${BKDIR}/${file}" "${KDIR}/klippy/extras/${file}"
    if ! grep -q "klippy/extras/${file}" "${KDIR}/.git/info/exclude"; then
        echo "klippy/extras/${file}" >> "${KDIR}/.git/info/exclude"
    fi
done

echo "Cartographer Probe: installation successful."
