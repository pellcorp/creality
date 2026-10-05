#!/bin/sh

if [ "$1" != "simpleaf" ] && [ "$1" != "stock" ]; then
    echo "Invalid choice - must specify either simpleaf or stock!"
    exit 1
fi

if [ "$1" = "simpleaf" ]; then
    if [ -d /usr/data/printer_data/config/.fluidd-theme ]; then
        echo "Backing up existing Fluidd theme ..."
        rm -rf /usr/data/printer_data/config/.fluidd-theme-backup
        mv /usr/data/printer_data/config/.fluidd-theme /usr/data/printer_data/config/.fluidd-theme-backup || exit $?
    fi
    if [ -d /usr/data/printer_data/config/.theme ]; then
        echo "Backing up existing Mainsail theme ..."
        rm -rf /usr/data/printer_data/config/.theme-backup
        mv /usr/data/printer_data/config/.theme /usr/data/printer_data/config/.theme-backup || exit $?
    fi

    echo "Applying Simple AF Fluidd theme ..."
    mkdir -p /usr/data/printer_data/config/.fluidd-theme || exit $?
    cp /usr/data/pellcorp/config/fluidd-theme/custom.css /usr/data/printer_data/config/.fluidd-theme/ || exit $?
    cp /usr/data/pellcorp/config/fluidd-theme/background.gif /usr/data/printer_data/config/.fluidd-theme/ || exit $?
    cp /usr/data/pellcorp/config/fluidd-theme/logo_SimpleAF.svg /usr/data/printer_data/config/.fluidd-theme/ || exit $?
    cp /usr/data/pellcorp/config/fluidd-theme/background-logo.svg /usr/data/printer_data/config/.fluidd-theme/ || exit $?
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
        -d '{"namespace":"fluidd","key":"uiSettings.theme","value":{"isDark":true,"logo":{"src":"logo_fluidd.svg"},"color":"#5a7df2","backgroundLogo":true}}' > /dev/null

    echo "Applying Simple AF Mainsail theme ..."
    mkdir -p /usr/data/printer_data/config/.theme || exit $?
    cp /usr/data/pellcorp/config/mainsail-theme/custom.css /usr/data/printer_data/config/.theme/ || exit $?
    cp /usr/data/pellcorp/config/mainsail-theme/background.gif /usr/data/printer_data/config/.theme/ || exit $?
    cp /usr/data/pellcorp/config/mainsail-theme/sidebar-logo.svg /usr/data/printer_data/config/.theme/ || exit $?
    cp /usr/data/pellcorp/config/mainsail-theme/background-logo.svg /usr/data/printer_data/config/.theme/ || exit $?
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
        -d '{"namespace":"mainsail","key":"uiSettings.mode","value":"dark"}' > /dev/null
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
        -d '{"namespace":"mainsail","key":"uiSettings.primary","value":"#5a7df2"}' > /dev/null
else # stock
    if [ -d /usr/data/printer_data/config/.fluidd-theme-backup ]; then
        echo "Restoring previous Fluidd theme ..."
        rm -rf /usr/data/printer_data/config/.fluidd-theme
        mv /usr/data/printer_data/config/.fluidd-theme-backup /usr/data/printer_data/config/.fluidd-theme
    else
        echo "Removing Simple AF Fluidd theme ..."
        rm -rf /usr/data/printer_data/config/.fluidd-theme
        curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=fluidd&key=uiSettings.theme" > /dev/null
    fi

    if [ -d /usr/data/printer_data/config/.theme-backup ]; then
        echo "Restoring previous Mainsail theme ..."
        rm -rf /usr/data/printer_data/config/.theme
        mv /usr/data/printer_data/config/.theme-backup /usr/data/printer_data/config/.theme
    else
        echo "Removing Simple AF Mainsail theme ..."
        rm -rf /usr/data/printer_data/config/.theme
        curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.mode" > /dev/null
        curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.primary" > /dev/null
    fi
fi
