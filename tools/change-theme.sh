#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi

THEMES_API=https://api.github.com/repos/pellcorp/simple-af-themes/git/trees/main?recursive=1
THEMES_URL=https://raw.githubusercontent.com/pellcorp/simple-af-themes/main
THEMES_DIR=/tmp/simple-af-themes

get_ini() {
    sed -n "s/^$2[[:space:]]*[:=][[:space:]]*//p" $1 | tr -d '\r' | head -1
}

# only downloads the theme files matching the pattern
download_files() {
    rm -rf $THEMES_DIR
    mkdir -p $THEMES_DIR
    for file in $(curl -fsL "$THEMES_API" | sed -n 's/.*"path": *"\([^"]*\)".*/\1/p' | grep -E "$1"); do
        mkdir -p $(dirname $THEMES_DIR/$file)
        curl -fsL $THEMES_URL/$file -o $THEMES_DIR/$file
    done
}

theme=$1
if [ "$theme" = "list" ]; then
    download_files "^[a-z0-9_-]+/theme\.ini$"
    echo "simpleaf - The default Simple AF theme"
    echo "stock - Removes any theme"
    for ini in $THEMES_DIR/*/theme.ini; do
        name=$(basename $(dirname $ini))
        [ -f $ini ] && [ "$name" != "template" ] && echo "$name - $(get_ini $ini name) by $(get_ini $ini author)"
    done
    rm -rf $THEMES_DIR
    exit 0
fi

case "$theme" in
    ""|template|*[!a-z0-9_-]*)
        echo "Invalid choice - must specify simpleaf, stock, list or a theme from https://github.com/pellcorp/simple-af-themes"
        exit 1
        ;;
esac

if [ "$theme" != "simpleaf" ] && [ "$theme" != "stock" ]; then
    echo "Downloading $theme theme ..."
    download_files "^$theme/(theme\.ini|css/[^/]+|svgs/[^/]+)$"
    theme_dir=$THEMES_DIR/$theme
    if [ ! -f $theme_dir/theme.ini ] || ([ ! -f $theme_dir/css/fluidd.css ] && [ ! -f $theme_dir/css/mainsail.css ]); then
        echo "ERROR: Theme $theme not found"
        rm -rf $THEMES_DIR
        exit 1
    fi
fi

# any existing custom theme is always wiped, there is no backup
rm -rf $BASEDIR/printer_data/config/.fluidd-theme
rm -rf $BASEDIR/printer_data/config/.theme

if [ "$theme" = "simpleaf" ]; then
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
elif [ "$theme" = "stock" ]; then
    echo "Removing Simple AF Fluidd and Mainsail themes ..."
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=fluidd&key=uiSettings.theme" > /dev/null
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.mode" > /dev/null
    curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.primary" > /dev/null
else
    color=$(get_ini $theme_dir/theme.ini color)
    echo "$color" | grep -Eq "^#[0-9a-fA-F]{6}$" || color="#3185a9"
    dark=true
    mode=dark
    if [ "$(get_ini $theme_dir/theme.ini dark)" = "false" ]; then
        dark=false
        mode=light
    fi

    if [ -f $theme_dir/css/fluidd.css ]; then
        echo "Applying $theme Fluidd theme ..."
        mkdir -p $BASEDIR/printer_data/config/.fluidd-theme || exit $?
        [ -d $theme_dir/svgs ] && cp $theme_dir/svgs/* $BASEDIR/printer_data/config/.fluidd-theme/
        cp $theme_dir/css/fluidd.css $BASEDIR/printer_data/config/.fluidd-theme/custom.css || exit $?
        logo="logo_fluidd.svg"
        [ -f $theme_dir/svgs/logo.svg ] && logo="server/files/config/.fluidd-theme/logo.svg"
        curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
            -d '{"namespace":"fluidd","key":"uiSettings.theme","value":{"isDark":'$dark',"logo":{"src":"'$logo'"},"color":"'$color'","backgroundLogo":true}}' > /dev/null
    else
        curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=fluidd&key=uiSettings.theme" > /dev/null
    fi

    if [ -f $theme_dir/css/mainsail.css ]; then
        echo "Applying $theme Mainsail theme ..."
        mkdir -p $BASEDIR/printer_data/config/.theme || exit $?
        [ -d $theme_dir/svgs ] && cp $theme_dir/svgs/* $BASEDIR/printer_data/config/.theme/
        cp $theme_dir/css/mainsail.css $BASEDIR/printer_data/config/.theme/custom.css || exit $?
        curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
            -d '{"namespace":"mainsail","key":"uiSettings.mode","value":"'$mode'"}' > /dev/null
        curl -s -X POST "http://localhost:7125/server/database/item" -H "Content-Type: application/json" \
            -d '{"namespace":"mainsail","key":"uiSettings.primary","value":"'$color'"}' > /dev/null
    else
        curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.mode" > /dev/null
        curl -s -X DELETE "http://localhost:7125/server/database/item?namespace=mainsail&key=uiSettings.primary" > /dev/null
    fi
    rm -rf $THEMES_DIR
fi
