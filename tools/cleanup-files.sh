#!/bin/sh

BASEDIR=$USER
IS_K1=false
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
    IS_K1=true
fi

# for K1 only we want to get the timestamp before ntp starts
start_timestamp=$(date +%s)

log() {
    local msg="$1"
    if [ "$client" = "true" ]; then
        echo "$msg" | tee -a $BASEDIR/cleanup.log
    else
        echo "$msg" >> $BASEDIR/cleanup.log
    fi
}

delete() {
    local file="$1"

    if [ "$dryrun" = "true" ]; then
        log "[Dryrun] Deleting $file"
    else
        log "Deleting $file"
        rm $file
    fi
}

if [ -f $BASEDIR/cleanup.log ]; then
    rm $BASEDIR/cleanup.log
    sync
fi

client=false
dryrun=false
while true; do
    if [ "$1" = "--dry-run" ]; then
        dryrun=true
        client=true
        shift
    elif [ "$1" = "--client" ]; then
        client=true
        shift
    else # no more parameters
        break
    fi
done

# kill pip cache to free up overlayfs
if [ -d /root/.cache ]; then
    rm -rf /root/.cache
    sync
fi

if [ "$IS_K1" = "true" ]; then
    # this is required because K series boards do not have a RTC, so it 2020 when it
    # gets turned on until ntp gets started, so we are looking for a massive drift jump
    # to know that ntp kicked in and finished its sync.   This script gets started
    # well before ntp does.
    if [ "$dryrun" != "true" ] || [ "$client" != "true" ]; then
        # this is jan 10 2025
        if [ $start_timestamp -lt 1583064047 ]; then
            log "Waiting for clock to sync..."
            while true; do
                timestamp=$(date +%s)
                drift=$(($timestamp-$start_timestamp))
                # drift of more than 20 minutes from start time stamp should be sufficient
                if [ $drift -gt 1200000 ]; then
                    break
                else
                    sleep 1s
                fi
            done
        fi
    fi

    # clear out tmp dir
    files=$(find $BASEDIR/tmp -type f -mtime 0 -print)
    for file in $files; do
        filename=$(basename $file)
        if [ "$filename" != "moonraker_instance_ids" ]; then
            delete $file
        fi
    done
    sync
fi

# if there is less than 1GB left, activate deletion of old gcode files
REMAINING_DISK=$(df -m $BASEDIR | tail -1 | awk '{print $4}')
if [ $REMAINING_DISK -lt 1000 ]; then
    log "Performing gcode cleanup"
    files=$(find $BASEDIR/printer_data/gcodes/ -maxdepth 1 -name "*.gcode" -type f -mtime +7 -print)
    for file in $files; do
        delete $file
    done
fi
sync

# we no longer create old style backups
files=$(find $BASEDIR/backups/ -maxdepth 1 -name "*.override.bkp" -type f -mtime 0 -print)
for file in $files; do
    delete $file
done
sync

# we no longer create these old style backup files
files=$(find $BASEDIR/backups/ -maxdepth 1 -name "printer-*.cfg" -type f -mtime 0 -print)
for file in $files; do
    delete $file
done
sync

files=$(find $BASEDIR/printer_data/logs/ -maxdepth 1 -name "*.log" -type f -mtime +7 -print)
for file in $files; do
    filename=$(basename $file)
    # lets just make sure we do not delete these files accidentally
    if [ "$filename" != "moonraker.log" ] && [ "$filename" != "grumpyscreen.log" ] && [ "$filename" != "klippy.log" ]; then
        delete $file
    fi
done
sync

# clean out backup tar balls
files=$(find $BASEDIR/backups/ -maxdepth 1 -name "backup-*.tar.gz" -type f -mtime +7 -print | sort -r)
# for simplicity sake always skip the newest old file in case its the only file left
skipped=false
for file in $files; do
    if [ "$skipped" = "false" ]; then
        skipped=true
    else
        delete $file
    fi
done
sync

# old save and restart config files
files=$(find $BASEDIR/printer_data/config/ -maxdepth 1 -name "printer-*.cfg" -type f -mtime +7 -print | sort -r)
# for simplicity sake always skip the newest old file in case its the only file left
skipped=false
for file in $files; do
    if [ "$skipped" = "false" ]; then
        skipped=true
    else
        delete $file
    fi
done
sync
