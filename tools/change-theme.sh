#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi

if [ "$1" != "simpleaf" ] && [ "$1" != "stock" ]; then
    echo "Invalid choice - must specify either simpleaf or stock!"
    exit 1
fi

# any existing custom theme is always wiped, there is no backup
rm -rf $BASEDIR/printer_data/config/.fluidd-theme
rm -rf $BASEDIR/printer_data/config/.theme

if [ "$1" = "simpleaf" ]; then
    echo "Applying Simple AF Fluidd and Mainsail themes ..."
    mkdir -p $BASEDIR/printer_data/config/.fluidd-theme || exit $?
    cp $BASEDIR/pellcorp/config/theme/logo_simpleaf.svg $BASEDIR/printer_data/config/.fluidd-theme/logo.svg || exit $?
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
            -d '{"namespace":"fluidd","key":"uiSettings.theme","value":{"isDark":true,"logo":{"src":"server/files/config/.fluidd-theme/logo.svg"},"color":"#3185a9","backgroundLogo":true}}' > /dev/null
    mkdir -p $BASEDIR/printer_data/config/.theme || exit $?
    cp $BASEDIR/pellcorp/config/theme/logo_simpleaf.svg $BASEDIR/printer_data/config/.theme/sidebar-logo.svg || exit $?
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
        -d '{"namespace":"mainsail","key":"uiSettings.mode","value":"dark"}' > /dev/null
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
        -d '{"namespace":"mainsail","key":"uiSettings.primary","value":"#3185a9"}' > /dev/null
else
    echo "Removing Simple AF Fluidd and Mainsail themes ..."
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=fluidd&key=uiSettings.theme" > /dev/null
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.mode" > /dev/null
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.primary" > /dev/null
fi
