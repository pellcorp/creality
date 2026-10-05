#!/bin/sh

if [ "$1" != "simpleaf" ] && [ "$1" != "stock" ]; then
    echo "Invalid choice - must specify either simpleaf or stock!"
    exit 1
fi

# any existing custom theme is always wiped, there is no backup
rm -rf /usr/data/printer_data/config/.fluidd-theme
rm -rf /usr/data/printer_data/config/.theme

if [ "$1" = "simpleaf" ]; then
    echo "Applying Simple AF Fluidd theme ..."
    mkdir -p /usr/data/printer_data/config/.fluidd-theme || exit $?
    cp /usr/data/pellcorp/config/fluidd-theme/custom.css /usr/data/printer_data/config/.fluidd-theme/ || exit $?
    cp /usr/data/pellcorp/config/fluidd-theme/logo_SimpleAF.svg /usr/data/printer_data/config/.fluidd-theme/ || exit $?
    cp /usr/data/pellcorp/config/fluidd-theme/background-logo.svg /usr/data/printer_data/config/.fluidd-theme/ || exit $?
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
        -d '{"namespace":"fluidd","key":"uiSettings.theme","value":{"isDark":true,"logo":{"src":"logo_fluidd.svg"},"color":"#5a7df2","backgroundLogo":true}}' > /dev/null

    echo "Applying Simple AF Mainsail theme ..."
    mkdir -p /usr/data/printer_data/config/.theme || exit $?
    cp /usr/data/pellcorp/config/mainsail-theme/custom.css /usr/data/printer_data/config/.theme/ || exit $?
    cp /usr/data/pellcorp/config/mainsail-theme/sidebar-logo.svg /usr/data/printer_data/config/.theme/ || exit $?
    cp /usr/data/pellcorp/config/mainsail-theme/background-logo.svg /usr/data/printer_data/config/.theme/ || exit $?
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
        -d '{"namespace":"mainsail","key":"uiSettings.mode","value":"dark"}' > /dev/null
    curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
        -d '{"namespace":"mainsail","key":"uiSettings.primary","value":"#5a7df2"}' > /dev/null
else # stock
    echo "Removing Simple AF Fluidd and Mainsail themes ..."
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=fluidd&key=uiSettings.theme" > /dev/null
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.mode" > /dev/null
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.primary" > /dev/null
fi
