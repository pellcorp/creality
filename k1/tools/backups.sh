#!/bin/sh

# for backups we are silent unless there is a disk space issue
REMAINING_ROOT_DISK=$(df -m / | tail -1 | awk '{print $4}')
if [ $REMAINING_ROOT_DISK -le 25 ]; then
    echo "CRITICAL: Remaining / space is critically low!"
    echo "CRITICAL: There is $(df -h / | tail -1 | awk '{print $4}') remaining on your / partition"
    exit 1
fi

REMAINING_TMP_DISK=$(df -m /tmp | tail -1 | awk '{print $4}')
if [ $REMAINING_TMP_DISK -le 25 ]; then
    echo "CRITICAL: Remaining /tmp space is critically low!"
    echo "CRITICAL: There is $(df -h /tmp | tail -1 | awk '{print $4}') remaining on your /tmp partition"
    exit 1
fi

REMAINING_DATA_DISK=$(df -m /usr/data | tail -1 | awk '{print $4}')
if [ $REMAINING_DATA_DISK -le 1000 ]; then
    echo "CRITICAL: Remaining disk space is critically low!"
    echo "CRITICAL: There is $(df -h /usr/data | tail -1 | awk '{print $4}') remaining on your /usr/data partition"
    exit 1
fi

mode=
restore=
while true; do
    if [ "$1" = "--create" ]; then
        mode=create
        shift
    elif [ "$1" = "--latest" ]; then
        shift
        mode=latest
    elif [ "$1" = "--list" ]; then
        shift
        mode=list
    elif [ "$1" = "--restore" ]; then
        shift
        mode=restore
        restore=$1
        shift

        if [ "$restore" = "latest" ]; then
            if [ -d /usr/data/printer_data/config/backups ] && [ $(ls -lt /usr/data/printer_data/config/backups/*.tar.gz 2> /dev/null | wc -l) -gt 0 ]; then
                restore=$(ls -lt /usr/data/printer_data/config/backups/*.tar.gz 2> /dev/null | head -1 | awk '{print $9}' | awk -F '/' '{print $7}')
            else
                echo "ERROR: No backups found"
                exit 1
            fi
        fi

        if [ ! -f /usr/data/printer_data/config/backups/$restore ]; then
            echo "ERROR: Backup /usr/data/printer_data/config/backups/$restore not found!"
            exit 1
        fi

    else # no more parameters
        break
    fi
done

if [ "$mode" = "create" ]; then
    if [ -z "$TIMESTAMP" ]; then
        export TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    fi

    cd /usr/data
    CFG_ARG='printer_data/config/*.cfg'
    CONF_ARG=''
    ls printer_data/config/*.conf > /dev/null 2>&1
    # straight from a factory reset, there will be no conf files
    if [ $? -eq 0 ]; then
        CONF_ARG='printer_data/config/*.conf'
    fi

    PELLCORP_BACKUPS=''
    if [ -d pellcorp-backups ]; then
        PELLCORP_BACKUPS='pellcorp-backups/*'
    fi

    PELLCORP_OVERRIDES=''
    if [ -d pellcorp-overrides ]; then
        PELLCORP_OVERRIDES='pellcorp-overrides/*'
    fi

    PELLCORP_DONE=''
    if [ -f pellcorp.done ]; then
        PELLCORP_DONE=pellcorp.done
    fi

    tar -zcf /usr/data/printer_data/config/backups/backup-${TIMESTAMP}.tar.gz $CFG_ARG $CONF_ARG $PELLCORP_BACKUPS $PELLCORP_OVERRIDES $PELLCORP_DONE
    sync

    cd - > /dev/null
    exit 0
elif [ "$mode" = "latest" ]; then
    if [ -d /usr/data/printer_data/config/backups ] && [ $(ls -lt /usr/data/printer_data/config/backups/*.tar.gz 2> /dev/null | wc -l) -gt 0 ]; then
        latest=$(ls -lt /usr/data/printer_data/config/backups/*.tar.gz 2> /dev/null | head -1 | awk '{print $9}' | awk -F '/' '{print $7}')
        if [ -n "$latest" ]; then
            echo "$latest"
            exit 0
        else
            echo "ERROR: No latest backup found"
            exit 1
        fi
    else
        echo "ERROR: No backups found"
        exit 1
    fi
elif [ "$mode" = "list" ]; then
    if [ -d /usr/data/printer_data/config/backups ] && [ $(ls -lt /usr/data/printer_data/config/backups/*.tar.gz 2> /dev/null | wc -l) -gt 0 ]; then
        ls -lt /usr/data/printer_data/config/backups/*.tar.gz 2> /dev/null | awk '{print $9}' | awk -F '/' '{print $7}'
        exit 0
    else
        echo "ERROR: No backups found"
        exit 1
    fi
elif [ "$mode" = "restore" ] && [ -f /usr/data/printer_data/config/backups/$restore ]; then
    echo "INFO: Restoring /usr/data/printer_data/config/backups/$restore ..."

    # ensure the backup file is suitable for an automatic restore, older backups which do not include
    # pellcorp-overrides, pellcorp.done and pellcorp-backups are not suitable for an automatic restore
    # because they do not restore the entire state of the printer and will result in subsequent updates
    # making matters much much worse.
    backup_files=$(tar -ztvf /usr/data/printer_data/config/backups/$restore)
    valid_backup=true
    if [ $(echo "$backup_files" | grep "pellcorp-overrides/" | wc -l) -eq 0 ]; then
        echo "ERROR: This backup cannot be used to do a full restoration - it is missing pellcorp-overrides/"
        valid_backup=false
    fi
    if [ $(echo "$backup_files" | grep "pellcorp-backups/" | wc -l) -eq 0 ]; then
        echo "ERROR: This backup cannot be used to do a full restoration - it is missing pellcorp-backups/"
        valid_backup=false
    fi
    if [ $(echo "$backup_files" | grep "pellcorp.done" | wc -l) -eq 0 ]; then
        echo "ERROR: This backup cannot be used to do a full restoration - it is missing pellcorp.done"
        valid_backup=false
    fi
    if [ $(echo "$backup_files" | grep "printer_data/config/" | wc -l) -eq 0 ]; then
        echo "ERROR: This backup cannot be used to do a full restoration - it is missing printer_data/config/"
        valid_backup=false
    fi
    if [ "$valid_backup" = "false" ]; then
        exit 1
    fi

    if [ -d "/usr/data/pellcorp-overrides" ]; then
        if [ -d /usr/data/pellcorp-overrides.old ]; then
            rm -rf /usr/data/pellcorp-overrides.old
        fi
        mv /usr/data/pellcorp-overrides /usr/data/pellcorp-overrides.old
    fi

    if [ -d "/usr/data/pellcorp-backups" ]; then
        if [ -d /usr/data/pellcorp-backups.old ]; then
            rm -rf /usr/data/pellcorp-backups.old
        fi
        mv /usr/data/pellcorp-backups /usr/data/pellcorp-backups.old
    fi

    echo "Restoring $restore ..."
    tar -zxf /usr/data/printer_data/config/backups/$restore -C /usr/data
    sync

    echo "Restarting Klippper ..."
    /etc/init.d/S55klipper_service restart
    echo "Restarting Moonraker ..."
    /etc/init.d/S56moonraker_service restart
else
    echo "You have the following options for using:"
    echo "  $0 --create"
    echo "  $0 --latest"
    echo "  $0 --list"
    echo "  $0 --restore <backup file|latest>"
    exit 1
fi
