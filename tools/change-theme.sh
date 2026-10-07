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
        echo "Invalid choice - must specify stock, list or a theme from https://github.com/pellcorp/simple-af-themes"
        exit 1
        ;;
esac

if [ "$theme" != "stock" ]; then
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
