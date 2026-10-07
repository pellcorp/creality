#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi

THEMES_API=https://api.github.com/repos/pellcorp/simple-af-themes/contents
THEMES_URL=https://raw.githubusercontent.com/pellcorp/simple-af-themes/main
THEMES_DIR=/tmp/simple-af-themes

theme=$1
if [ "$theme" = "list" ]; then
    echo "stock"
    curl -fsL $THEMES_API | sed -n 's/.*"name": *"\([a-z0-9_-]*\)\.zip".*/\1/p'
    exit 0
fi

case "$theme" in
    ""|*[!a-z0-9_-]*)
        echo "Invalid choice - must specify stock, list or a theme from https://github.com/pellcorp/simple-af-themes"
        exit 1
        ;;
esac

if [ "$theme" != "stock" ]; then
    echo "Downloading $theme theme ..."
    rm -rf $THEMES_DIR
    mkdir -p $THEMES_DIR
    theme_dir=$THEMES_DIR/$theme
    if ! curl -fsL $THEMES_URL/$theme.zip -o $THEMES_DIR/$theme.zip || ! unzip -qo $THEMES_DIR/$theme.zip -d $theme_dir; then
        echo "ERROR: Theme $theme not found"
        rm -rf $THEMES_DIR
        exit 1
    fi
    if [ ! -f $theme_dir/css/fluidd.css ] && [ ! -f $theme_dir/css/mainsail.css ]; then
        echo "ERROR: Theme $theme is invalid"
        rm -rf $THEMES_DIR
        exit 1
    fi
fi

# any existing custom theme is always wiped, there is no backup
rm -rf $BASEDIR/printer_data/config/.fluidd-theme
rm -rf $BASEDIR/printer_data/config/.theme

if [ "$theme" = "stock" ]; then
    mkdir -p $BASEDIR/printer_data/config/.theme || exit $?
    cp $BASEDIR/pellcorp/config/theme/logo_simpleaf.svg $BASEDIR/printer_data/config/.theme/sidebar-logo.svg || exit $?

    mkdir -p $BASEDIR/printer_data/config/.fluidd-theme || exit $?
    cp $BASEDIR/pellcorp/config/theme/logo_simpleaf.svg $BASEDIR/printer_data/config/.fluidd-theme/logo.svg || exit $?
    # fluidd docs are wrong you can't drop a logo.svg into the fluidd theme directory, I opened a bug maybe they
    # actually change the code so it can actually work and I can remove this shit
    curl -s -X POST "http://localhost:7125/server/database/item" \
        -H "Content-Type: application/json" \
        -d '{"namespace":"fluidd","key":"uiSettings.theme.logo.src","value":"server/files/config/.fluidd-theme/logo.svg"}' > /dev/null

    echo "Removed Fluidd and Mainsail themes"
    exit 0
fi

if [ -f $theme_dir/css/fluidd.css ]; then
    echo "Applying $theme Fluidd theme ..."
    mkdir -p $BASEDIR/printer_data/config/.fluidd-theme || exit $?
    [ -d $theme_dir/svgs ] && cp $theme_dir/svgs/* $BASEDIR/printer_data/config/.fluidd-theme/
    cp $theme_dir/css/fluidd.css $BASEDIR/printer_data/config/.fluidd-theme/custom.css || exit $?
fi

if [ -f $theme_dir/css/mainsail.css ]; then
    echo "Applying $theme Mainsail theme ..."
    mkdir -p $BASEDIR/printer_data/config/.theme || exit $?
    [ -d $theme_dir/svgs ] && cp $theme_dir/svgs/* $BASEDIR/printer_data/config/.theme/
    cp $theme_dir/css/mainsail.css $BASEDIR/printer_data/config/.theme/custom.css || exit $?
fi
rm -rf $THEMES_DIR
