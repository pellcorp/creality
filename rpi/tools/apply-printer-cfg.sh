#!/bin/bash

BASEDIR=$HOME
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
mode=apply

if [ $# -eq 0 ]; then
    echo "Usage: $0 [--verify] <printer>"
    exit 1
fi

if [ "$1" = "--verify" ]; then
    mode=verify
    shift
fi
printer=$1

if [[ "$printer" == *\/* ]] && [ -f $printer ]; then
    printer_cfg=$(realpath $printer)
    if [ "$mode" = "verify" ]; then
        # for a arbitrary file we want to validate it was downloaded correctly
        kinematics=$($CONFIG_HELPER --file $printer_cfg --get-section-entry "printer" "kinematics" 2> /dev/null)
        if [ -z "$kinematics" ]; then
            echo "ERROR: Invalid printer configuration file"
            exit 1
        fi
    fi
elif [ -f "$BASEDIR/pellcorp/rpi/printers/${printer}.cfg" ]; then
    printer_cfg=$BASEDIR/pellcorp/rpi/printers/${printer}.cfg
else
    echo "ERROR: Invalid printer (${printer}) specified"
    if [ "$mode" = "verify" ]; then
        echo "The following printers are supported:"
        echo
        files=$(find $BASEDIR/pellcorp/rpi/printers -maxdepth 1 -name "*.cfg")
        for file in $files; do
            file=$(basename $file .cfg)
            comment=$(cat $BASEDIR/pellcorp/rpi/printers/${file}.cfg | grep "^#" | head -1 | sed 's/#\s*//g')
            echo "  * $file - $comment"
        done
    fi
    exit 1
fi

model=$(cat $printer_cfg | grep MODEL: | awk -F ':' '{print $2}')
if [ -z "$model" ]; then
    model=unspecified
fi

if [ "$mode" = "verify" ]; then
    exit 0
fi

# save a reference to what printer was chosen
echo "printer=$printer" > $BASEDIR/pellcorp-overrides/config.info

mkdir -p $BASEDIR/pellcorp-backups
rm $BASEDIR/pellcorp-backups/*.factory.cfg 2> /dev/null

if grep -q "^-- printer.cfg" $printer_cfg; then
    file=
    while IFS= read -r line; do
        if echo "$line" | grep -q "^--"; then
            file=$(echo $line | sed 's/-- //g' | sed 's/.cfg//g')
            if [ -n "$model" ] && [ "$file" = "printer" ] && [ ! -f $BASEDIR/pellcorp-backups/printer.factory.cfg ]; then
                echo "# MODEL:$model" > $BASEDIR/pellcorp-backups/printer.factory.cfg
            else
                touch $BASEDIR/pellcorp-backups/${file}.factory.cfg
            fi
        elif echo "$line" | grep -q "^#"; then
            continue # skip comments
        elif [ -n "$file" ] && [ -f $BASEDIR/pellcorp-backups/${file}.factory.cfg ]; then
            echo "$line" >> $BASEDIR/pellcorp-backups/${file}.factory.cfg
        fi
    done < "$printer_cfg"
else
    cp $printer_cfg $BASEDIR/pellcorp-backups/printer.factory.cfg
fi

if [ -f $BASEDIR/pellcorp-backups/printer.factory.cfg ]; then
    exit 0
else
    echo "ERROR: Missing printer.cfg file"
    exit 1
fi
