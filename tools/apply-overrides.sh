#!/bin/sh

BASEDIR=/home/pi
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"

function apply_guppyscreen_overrides() {
    command=""
    for entry in display_brightness invert_z_icon display_sleep_sec theme touch_calibration_coeff; do
      value=$(cat $BASEDIR/pellcorp-overrides/guppyscreen.json | grep "${entry}=" | awk -F '=' '{print $2}')
      if [ -n "$value" ]; then
          if [ -n "$command" ]; then
              command="$command | "
          fi
          if [ "$entry" = "theme" ]; then
              command="${command}.${entry} = \"$value\""
          else
              command="${command}.${entry} = $value"
          fi
      fi
    done

    if [ -n "$command" ]; then
        echo "Applying overrides $BASEDIR/guppyscreen/guppyscreen.json ..."
        jq "$command" $BASEDIR/guppyscreen/guppyscreen.json > $BASEDIR/guppyscreen/guppyscreen.json.$$
        mv $BASEDIR/guppyscreen/guppyscreen.json.$$ $BASEDIR/guppyscreen/guppyscreen.json
    fi
}

function apply_overrides() {
    return_status=0
    if [ -f $BASEDIR/pellcorp-overrides.cfg ] || [ -d $BASEDIR/pellcorp-overrides ]; then
        echo
        echo "INFO: Applying overrides ..."

        overrides_dir=$BASEDIR/pellcorp-overrides
        if [ -f $BASEDIR/pellcorp-overrides.cfg ]; then
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
            done < "$BASEDIR/pellcorp-overrides.cfg"
        fi

        files=$(find $overrides_dir -maxdepth 1 ! -name 'printer-*.cfg' -a ! -name ".printer.cfg" -a -name "*.cfg" -o -name "*.conf" -o -name "*.json" -o -name "printer.cfg.save_config")
        for file in $files; do
            file=$(basename $file)

            # check to see if we need to handle any legacy -k1.cfg / -k1m.cfg / -f004.cfg overrides
            base_file=$(echo "$file" | sed "s/-${model}//g")
            if [ "$base_file" = "cartographer.cfg" ] && [ -f $BASEDIR/printer_data/config/cartotouch.cfg ]; then
                base_file=cartotouch.cfg
            elif [ "$base_file" = "btteddy.cfg" ] && [ -f $BASEDIR/printer_data/config/eddyng.cfg ]; then
                base_file=eddyng.cfg
            fi

            # special case for moonraker.secrets
            if [ "$file" != "$base_file" ] && [ -f "$BASEDIR/pellcorp/k1/$base_file" ] && [ -f $BASEDIR/printer_data/config/${base_file} ]; then
                $CONFIG_HELPER --file ${base_file} --overrides $overrides_dir/$file || exit $?
            elif [ "$file" = "moonraker.secrets" ]; then
                echo "INFO: Restoring $BASEDIR/printer_data/$file ..."
                cp $overrides_dir/$file $BASEDIR/printer_data/
            elif [ "$file" = "guppyscreen.json" ]; then
                apply_guppyscreen_overrides
            elif [ "$file" = "KAMP_Settings.cfg" ]; then # KAMP_Settings.cfg is gone apply any overrides to start_end.cfg
                # remove any overrides for these values which do not apply to Smart Park and Line Purge
                sed -i '/variable_verbose_enable/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
                sed -i '/variable_mesh_margin/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
                sed -i '/variable_fuzz_amount/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
                sed -i '/variable_probe_dock_enable/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
                sed -i '/variable_attach_macro/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
                sed -i '/variable_detach_macro/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg

                $CONFIG_HELPER --file start_end.cfg --overrides $overrides_dir/$file || exit $?
            elif [ -L $BASEDIR/printer_data/config/$file ] || [ "$file" = "useful_macros.cfg" ] || [ "$file" = "internal_macros.cfg" ] || [ "$file" = "belts_calibration.cfg" ]; then
                echo "WARN: Ignoring $file ..."
            elif [ -f "$BASEDIR/pellcorp-backups/$file" ] || [ -f "$BASEDIR/pellcorp/k1/$file" ]; then
                if [ -f $BASEDIR/printer_data/config/$file ]; then
                    # we renamed the SENSORLESS_PARAMS to hide it
                    if [ "$file" = "sensorless.cfg" ]; then
                        sed -i 's/gcode_macro SENSORLESS_PARAMS/gcode_macro _SENSORLESS_PARAMS/g' $BASEDIR/pellcorp-overrides/sensorless.cfg
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
                        $CONFIG_HELPER --file moonraker.conf --remove-section "update_manager cartographer"
                    fi
                fi
            elif [ "$file" != "printer.cfg.save_config" ]; then
                echo "INFO: Restoring $BASEDIR/printer_data/config/$file ..."
                cp $overrides_dir/$file $BASEDIR/printer_data/config/
            fi
            # fixme - we currently have no way to know if the file was updated assume if we got here it was
            return_status=1
        done

        # we want to apply the save config last
        if [ -f $overrides_dir/printer.cfg.save_config ]; then
            # if the printer.cfg already has SAVE_CONFIG skip applying it again
            if ! grep -q "#*# <---------------------- SAVE_CONFIG ---------------------->" $BASEDIR/printer_data/config/printer.cfg ; then
                echo "INFO: Applying save config state to $BASEDIR/printer_data/config/printer.cfg"
                echo "" >> $BASEDIR/printer_data/config/printer.cfg
                cat $overrides_dir/printer.cfg.save_config >> $BASEDIR/printer_data/config/printer.cfg
                return_status=1
            else
                echo "WARN: Skipped applying save config state to $BASEDIR/printer_data/config/printer.cfg"
            fi
        fi

        if [ -d /tmp/overrides.$$ ]; then
            rm -rf /tmp/overrides.$$
        fi
        sync
    fi
    return $return_status
}

mkdir -p $BASEDIR/backups/
apply_overrides
exit $?
