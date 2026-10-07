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
