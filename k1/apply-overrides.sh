#!/bin/sh

CONFIG_HELPER="/usr/data/pellcorp/k1/config-helper.py"

function apply_overrides() {
    return_status=0
    if [ -f /usr/data/pellcorp-overrides.cfg ] || [ -d /usr/data/pellcorp-overrides ]; then
        echo ""
        echo "Applying overrides ..."

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

        files=$(find $overrides_dir ! -name 'printer-*.cfg' -a ! -name ".printer.cfg" -a -name "*.cfg" -o -name "*.conf" -o -name "printer.cfg.save_config")
        for file in $files; do
            file=$(basename $file)
            # special case for moonraker.secrets
            if [ "$file" = "moonraker.secrets" ]; then
                echo "Restoring /usr/data/printer_data/$file ..."
                cp $overrides_dir/$file /usr/data/printer_data/
            elif [ -L /usr/data/printer_data/config/$file ] || [ "$file" = "bltouch.cfg" ] || [ "$file" = "microprobe.cfg" ]; then
                echo "Ignoring $file ..."
            elif [ "$file" = "printer.cfg" ] || [ -f "/usr/data/pellcorp-backups/$file" ] || [ -f "/usr/data/pellcorp/k1/$file" ]; then
              if [ -f /usr/data/printer_data/config/$file ]; then
                echo "Applying overrides for /usr/data/printer_data/config/$file ..."
                cp /usr/data/printer_data/config/$file /usr/data/printer_data/config/${file}.override.bkp
                $CONFIG_HELPER --file $file --overrides $overrides_dir/$file || exit $?

                # if users had their own version of guppyscreen.cfg their config will break because I removed the guppy_module_loader
                # so be a nice to people and clean that shit up
                if [ "$file" = "guppyscreen.cfg" ]; then
                    /usr/data/pellcorp/k1/config-helper.py --file guppyscreen.cfg --remove-section guppy_module_loader
                fi
              else # if switching probes we might run into this
                echo "Ignoring overrides for missing /usr/data/printer_data/config/$file"
              fi
            elif [ "$file" != "printer.cfg.save_config" ]; then
                echo "Restoring /usr/data/printer_data/config/$file ..."
                cp $overrides_dir/$file /usr/data/printer_data/config/
            fi
            # fixme - we currently have no way to know if the file was updated assume if we got here it was
            return_status=1
        done

        # we want to apply the save config last
        if [ -f $overrides_dir/printer.cfg.save_config ]; then
          # if the printer.cfg already has SAVE_CONFIG skip applying it again
          if ! grep -q "#*# <---------------------- SAVE_CONFIG ---------------------->" /usr/data/printer_data/config/printer.cfg ; then
            echo "Applying SAVE_CONFIG state to /usr/data/printer_data/config/printer.cfg"
            echo "" >> /usr/data/printer_data/config/printer.cfg
            cat $overrides_dir/printer.cfg.save_config >> /usr/data/printer_data/config/printer.cfg
            return_status=1
          else
            echo "Skipped applying SAVE_CONFIG state to /usr/data/printer_data/config/printer.cfg"
          fi
        fi

        if [ -d /tmp/overrides.$$ ]; then
            rm -rf /tmp/overrides.$$
        fi
        sync
    fi
    return $return_status
}

apply_overrides
exit $?
