#!/bin/sh

OPERATION=cleanup-printer-cfg
ACTION=display
DAYS=7

if [ -n "$1" ]; then
    while true; do
        if [ "$1" = "--cleanup-backups" ]; then
            OPERATION=$(echo $1 | sed 's/--//g')
            shift
        elif [ "$1" = "--delete" ] || [ "$1" = "--display" ]; then
            ACTION=$(echo $1 | sed 's/--//g')
            shift
        elif [ "$1" = "--days" ] && [ -n "$2" ]; then
            DAYS=$2
            shift
            shift
        else # no more parameters
            break
        fi
    done
fi

echo "Operation $OPERATION"
echo "Action $ACTION"
echo "Days $DAYS"

if [ "$OPERATION" = "cleanup-backups" ]; then
    cd /usr/data/printer_data/config/
    files=$(find . -name "printer-*.cfg" -type f -mtime +$DAYS -print -o -name "backup-*.tar.gz" -type f -mtime +$DAYS -print)
    for file in $files; do
        if [ "$ACTION" = "delete" ]; then
            echo "Deleting $file ..."
            rm $file
        else
            echo "Would delete $file ..."
        fi
    done
fi
