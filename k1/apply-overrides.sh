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

        files=$(ls $overrides_dir)
        for file in $files; do
            
            # special case for moonraker.secrets
            if [ "$file" = "moonraker.secrets" ]; then
                echo "Restoring $file ..."
                cp $overrides_dir/$file /usr/data/printer_data/
            else
                echo "Applying overrides for $file ..."
                cp /usr/data/printer_data/config/$file /usr/data/printer_data/config/${file}.override.bkp
                $CONFIG_HELPER --file $file --overrides $overrides_dir/$file || exit $?
            fi
            # fixme - we currently have no way to know if the file was updated assume if we got here it was
            return_status=1
        done

        if [ -d /tmp/overrides.$$ ]; then
            rm -rf /tmp/overrides.$$
        fi
        sync
    fi
    return $return_status
}

apply_overrides
exit $?
