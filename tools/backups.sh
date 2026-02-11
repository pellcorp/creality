#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data

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
    
    REMAINING_DATA_DISK=$(df -m $BASEDIR | tail -1 | awk '{print $4}')
    if [ $REMAINING_DATA_DISK -le 1000 ]; then
        echo "CRITICAL: Remaining disk space is critically low!"
        echo "CRITICAL: There is $(df -h $BASEDIR | tail -1 | awk '{print $4}') remaining on your $BASEDIR partition"
        exit 1
    fi
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
            if [ -d $BASEDIR/backups ] && [ $(ls -lt $BASEDIR/backups/backup-*.tar.gz 2> /dev/null | wc -l) -gt 0 ]; then
                restore=$(ls -lt $BASEDIR/backups/backup-*.tar.gz 2> /dev/null | grep -v "backup-latest.tar.gz" | head -1 | awk '{print $9}' | awk -F '/' '{print $NF}')
            else
                echo "ERROR: No backups found"
                exit 1
            fi
        fi

        if [ ! -f $BASEDIR/backups/$restore ]; then
            echo "ERROR: Backup $BASEDIR/backups/$restore not found!"
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

    cd $BASEDIR
    CFG_ARG=''
    if ls printer_data/config/*.cfg > /dev/null 2>&1; then
        CFG_ARG='printer_data/config/*.cfg'
    fi

    CONF_ARG=''
    if ls printer_data/config/*.conf > /dev/null 2>&1; then
        CONF_ARG='printer_data/config/*.conf'
    fi

    PELLCORP_BACKUPS=''
    if ls pellcorp-backups/* > /dev/null 2>&1; then
        PELLCORP_BACKUPS='pellcorp-backups/*'
    fi

    PELLCORP_OVERRIDES=''
    if ls pellcorp-overrides/* > /dev/null 2>&1; then
        PELLCORP_OVERRIDES='pellcorp-overrides/*'
    fi

    PELLCORP_DONE=''
    if [ -f pellcorp.done ]; then
        PELLCORP_DONE=pellcorp.done
    fi

    if [ -n "$CFG_ARG" ] || [ -n "$CONF_ARG" ] || [ -n "$PELLCORP_BACKUPS" ] || [ -n "$PELLCORP_OVERRIDES" ] || [ -n "$PELLCORP_DONE" ]; then
        tar -zcf $BASEDIR/backups/backup-${TIMESTAMP}.tar.gz $CFG_ARG $CONF_ARG $PELLCORP_BACKUPS $PELLCORP_OVERRIDES $PELLCORP_DONE
        sync
    fi

    cd - > /dev/null
    exit 0
elif [ "$mode" = "latest" ]; then
    if [ -d $BASEDIR/backups ] && [ $(ls -lt $BASEDIR/backups/backup-*.tar.gz 2> /dev/null | wc -l) -gt 0 ]; then
        latest=$(ls -lt $BASEDIR/backups/backup-*.tar.gz 2> /dev/null | grep -v "backup-latest.tar.gz" | head -1 | awk '{print $9}' | awk -F '/' '{print $NF}')
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
    if [ -d $BASEDIR/backups ] && [ $(ls -lt $BASEDIR/backups/backup-*.tar.gz 2> /dev/null | wc -l) -gt 0 ]; then
        ls -lt $BASEDIR/backups/backup-*.tar.gz 2> /dev/null | grep -v "backup-latest.tar.gz" | awk '{print $9}' | awk -F '/' '{print $NF}'
        exit 0
    else
        echo "ERROR: No backups found"
        exit 1
    fi
elif [ "$mode" = "restore" ] && [ -f $BASEDIR/backups/$restore ]; then
    echo "INFO: Restoring $BASEDIR/backups/$restore ..."

    # ensure the backup file is suitable for an automatic restore, older backups which do not include
    # pellcorp-overrides, pellcorp.done and pellcorp-backups are not suitable for an automatic restore
    # because they do not restore the entire state of the printer and will result in subsequent updates
    # making matters much much worse.
    backup_files=$(tar -ztvf $BASEDIR/backups/$restore)
    valid_backup=true
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

    if [ -d "$BASEDIR/pellcorp-overrides" ]; then
        if [ -d $BASEDIR/pellcorp-overrides.old ]; then
            rm -rf $BASEDIR/pellcorp-overrides.old
        fi
        mv $BASEDIR/pellcorp-overrides $BASEDIR/pellcorp-overrides.old
    fi

    if [ -d "$BASEDIR/pellcorp-backups" ]; then
        if [ -d $BASEDIR/pellcorp-backups.old ]; then
            rm -rf $BASEDIR/pellcorp-backups.old
        fi
        mv $BASEDIR/pellcorp-backups $BASEDIR/pellcorp-backups.old
    fi

    if [ -d "$BASEDIR/printer_data/config" ]; then
        if [ -d $BASEDIR/printer_data/config.old ]; then
            rm -rf $BASEDIR/printer_data/config.old
        fi
        mv $BASEDIR/printer_data/config $BASEDIR/printer_data/config.old
    fi

    echo "Restoring $restore ..."
    tar -zxf $BASEDIR/backups/$restore -C $BASEDIR
    sync

    # make sure an empty directory gets created for a restoration
    mkdir -p $BASEDIR/pellcorp-overrides

    echo "Restarting Klippper ..."
    sudo systemctl restart klipper
    echo "Restarting Moonraker ..."
    sudo systemctl restart moonraker
else
    echo "You have the following options for using:"
    echo "  $0 --create"
    echo "  $0 --latest"
    echo "  $0 --list"
    echo "  $0 --restore <backup file|latest>"
    exit 1
fi
