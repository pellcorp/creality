#!/bin/sh

CONFIG_HELPER="/usr/data/pellcorp/k1/config-helper.py"

MODEL=$(/usr/bin/get_sn_mac.sh model)
if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ] || [ "$MODEL" = "K1 SE" ]; then
    model=k1
elif [ "$MODEL" = "CR-K1 Max" ] || [ "$MODEL" = "K1 Max SE" ]; then
    model=k1m
elif [ "$MODEL" = "F004" ]; then
    model=f004
else
    echo "This script is not supported for $MODEL!"
    exit 1
fi

function apply_overrides() {
    return_status=0
    if [ -f /usr/data/pellcorp-overrides.cfg ] || [ -d /usr/data/pellcorp-overrides ]; then
        echo
        echo "INFO: Applying overrides ..."

        overrides_dir=/usr/data/pellcorp-overrides
        if [ -f /usr/data/pellcorp-overrides.cfg ]; then
            overrides_dir=/tmp/overrides.$$
            mkdir $overrides_dir
            file=
            while IFS= read -r line; do
                echo "$line" | grep -q "\--"
                if [ $? -eq 0 ]; then
                    file=$(echo $line | sed 's/-- //g')
                    touch $overrides_dir/$file
                elif [ -n "$file" ] && [ -f $overrides_dir/$file ]; then
                    echo "$line" >> $overrides_dir/$file
                fi
            done < "/usr/data/pellcorp-overrides.cfg"
        fi

        files=$(find $overrides_dir -maxdepth 1 ! -name 'printer-*.cfg' -a ! -name ".printer.cfg" -a -name "*.cfg" -o -name "*.conf" -o -name "*.json" -o -name "printer.cfg.save_config")
        for file in $files; do
            file=$(basename $file)

            # check to see if we need to handle any legacy -k1.cfg / -k1m.cfg / -f004.cfg overrides
            base_file=$(echo "$file" | sed "s/-${model}//g")
            if [ "$base_file" = "cartographer.cfg" ] && [ -f /usr/data/printer_data/config/cartotouch.cfg ]; then
                base_file=cartotouch.cfg
            elif [ "$base_file" = "btteddy.cfg" ] && [ -f /usr/data/printer_data/config/eddyng.cfg ]; then
                base_file=eddyng.cfg
            fi

            # special case for moonraker.secrets
            if [ "$file" != "$base_file" ] && [ -f "/usr/data/pellcorp/k1/$base_file" ] && [ -f /usr/data/printer_data/config/${base_file} ]; then
                $CONFIG_HELPER --file ${base_file} --overrides $overrides_dir/$file || exit $?
            elif [ "$file" = "moonraker.secrets" ]; then
                echo "INFO: Restoring /usr/data/printer_data/$file ..."
                cp $overrides_dir/$file /usr/data/printer_data/
            elif [ "$file" = "guppyscreen.json" ]; then
                /usr/data/pellcorp/k1/update-guppyscreen.sh --apply-overrides
            elif [ -L /usr/data/printer_data/config/$file ] || [ "$file" = "useful_macros.cfg" ] || [ "$file" = "internal_macros.cfg" ] || [ "$file" = "guppyscreen.cfg" ]; then
                if [ "$file" = "guppyscreen.cfg" ]; then  # we removed guppy module loader completely
                    /usr/data/pellcorp/k1/config-helper.py --file guppyscreen.cfg --remove-section guppy_module_loader
                fi
                echo "WARN: Ignoring $file ..."
            elif [ -f "/usr/data/pellcorp-backups/$file" ] || [ -f "/usr/data/pellcorp/k1/$file" ]; then
                if [ -f /usr/data/printer_data/config/$file ]; then
                    # we renamed the SENSORLESS_PARAMS to hide it
                    if [ "$file" = "sensorless.cfg" ]; then
                        sed -i 's/gcode_macro SENSORLESS_PARAMS/gcode_macro _SENSORLESS_PARAMS/g' /usr/data/pellcorp-overrides/sensorless.cfg
                    fi

                    # we are migrating the bltouch and microprobe sections from printer.cfg to their own files, so we need to
                    # ignore any existing config overrides for these sections from printer.cfg, we won't try and automatically
                    # migrate them, as we have already done that for generating config overrides so the only time this
                    # will be an issue is for a factory reset with old overrides!
                    if [ "$file" = "printer.cfg" ]; then
                      $CONFIG_HELPER --file $file --overrides $overrides_dir/$file --exclude-sections probe,bltouch || exit $?
                    else
                      $CONFIG_HELPER --file $file --overrides $overrides_dir/$file || exit $?
                    fi
                    if [ "$file" = "moonraker.conf" ]; then  # we moved cartographer to a separate cartographer.conf include
                        /usr/data/pellcorp/k1/config-helper.py --file moonraker.conf --remove-section "update_manager cartographer"
                    fi
                fi
            elif [ "$file" != "printer.cfg.save_config" ]; then
                echo "INFO: Restoring /usr/data/printer_data/config/$file ..."
                cp $overrides_dir/$file /usr/data/printer_data/config/
            fi
            # fixme - we currently have no way to know if the file was updated assume if we got here it was
            return_status=1
        done

        # we want to apply the save config last
        if [ -f $overrides_dir/printer.cfg.save_config ]; then
            # if the printer.cfg already has SAVE_CONFIG skip applying it again
            if ! grep -q "#*# <---------------------- SAVE_CONFIG ---------------------->" /usr/data/printer_data/config/printer.cfg ; then
                echo "INFO: Applying save config state to /usr/data/printer_data/config/printer.cfg"
                echo "" >> /usr/data/printer_data/config/printer.cfg
                cat $overrides_dir/printer.cfg.save_config >> /usr/data/printer_data/config/printer.cfg
                return_status=1
            else
                echo "WARN: Skipped applying save config state to /usr/data/printer_data/config/printer.cfg"
            fi
        fi

        if [ -d /tmp/overrides.$$ ]; then
            rm -rf /tmp/overrides.$$
        fi
        sync
    fi
    return $return_status
}

mkdir -p /usr/data/printer_data/config/backups/
apply_overrides
exit $?
