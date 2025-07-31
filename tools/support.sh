#!/bin/sh

BASEDIR="$HOME"
TMPDIR="/tmp"

if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR="/usr/data"
    TMPDIR="$BASEDIR/tmp"

    # for backups we are silent unless there is a disk space issue
    REMAINING_ROOT_DISK=$(df -m / | tail -1 | awk '{print $4}')
    if [ "$REMAINING_ROOT_DISK" -le 25 ]; then
        echo "CRITICAL: Remaining / space is critically low!"
        echo "CRITICAL: There is $(df -h / | tail -1 | awk '{print $4}') remaining on your / partition"
        exit 1
    fi

    REMAINING_TMP_DISK=$(df -m /tmp | tail -1 | awk '{print $4}')
    if [ "$REMAINING_TMP_DISK" -le 25 ]; then
        echo "CRITICAL: Remaining /tmp space is critically low!"
        echo "CRITICAL: There is $(df -h /tmp | tail -1 | awk '{print $4}') remaining on your /tmp partition"
        exit 1
    fi

    REMAINING_DATA_DISK=$(df -m "$BASEDIR" | tail -1 | awk '{print $4}')
    if [ "$REMAINING_DATA_DISK" -le 1000 ]; then
        echo "CRITICAL: Remaining disk space is critically low!"
        echo "CRITICAL: There is $(df -h "$BASEDIR" | tail -1 | awk '{print $4}') remaining on your $BASEDIR partition"
        exit 1
    fi
fi

echo "Generating support.zip, please wait..."

rm -f "$BASEDIR/printer_data/config/support.tar.gz"
rm -f "$BASEDIR/support.zip"
rm -f "$BASEDIR/printer_data/config/support.zip"
rm -f "$BASEDIR/support.log"

DATE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
{
    echo "----------------------------------------------------------------------------"
    echo "Simple AF installation details ${DATE_TIME}"
    echo "---------------- top -------------------------------------------------------"
    top -b -n 1
    echo "---------------- free ------------------------------------------------------"
    free
    echo "---------------- lsusb -----------------------------------------------------"
    lsusb
    echo "---------------- ls -la /etc/init.d ----------------------------------------"
    ls -la /etc/init.d
    echo "---------------- ls -laR $BASEDIR -----------------------------------------"
    ls -laR "$BASEDIR"
    echo "----------------------------------------------------------------------------"
} >> "$BASEDIR/support.log"

if [ -f /var/log/messages ]; then
    cat /var/log/messages > "$TMPDIR/messages.log"
else
    sudo journalctl --dmesg > "$TMPDIR/messages.log"
fi

cd "$BASEDIR" || exit 1

latest_klippy_log=$(ls -Art printer_data/logs/klippy.log.* 2>/dev/null | tail -n 1)
if [ -z "$latest_klippy_log" ] || [ ! -f "$latest_klippy_log" ]; then
    unset latest_klippy_log
fi

# Prepare temporary working directory for packaging
WORKDIR="$TMPDIR/support_temp"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# Copy files/directories into staging area
cp "$BASEDIR/support.log" "$WORKDIR/" 2>/dev/null || true
cp "$TMPDIR/messages.log" "$WORKDIR/" 2>/dev/null || true

mkdir -p "$WORKDIR/pellcorp-overrides"
cp -r "$BASEDIR/pellcorp-overrides/"* "$WORKDIR/pellcorp-overrides/" 2>/dev/null || true

mkdir -p "$WORKDIR/pellcorp-backups"
cp -r "$BASEDIR/pellcorp-backups/"* "$WORKDIR/pellcorp-backups/" 2>/dev/null || true

mkdir -p "$WORKDIR/printer_data/config"
cp -r "$BASEDIR/printer_data/config/"* "$WORKDIR/printer_data/config/" 2>/dev/null || true

mkdir -p "$WORKDIR/printer_data/logs"
cp "$BASEDIR"/printer_data/logs/installer-*.log "$WORKDIR/printer_data/logs/" 2>/dev/null || true
cp "$BASEDIR/printer_data/logs/klippy.log" "$WORKDIR/printer_data/logs/" 2>/dev/null || true
[ -n "$latest_klippy_log" ] && cp "$latest_klippy_log" "$WORKDIR/printer_data/logs/" 2>/dev/null || true
cp "$BASEDIR/printer_data/logs/moonraker.log" "$WORKDIR/printer_data/logs/" 2>/dev/null || true
cp "$BASEDIR/printer_data/logs/guppyscreen.log" "$WORKDIR/printer_data/logs/" 2>/dev/null || true

# Strip any .git directories
find "$WORKDIR" -type d -name ".git" -exec rm -rf {} +

# Create ZIP archive
cd "$WORKDIR" || exit 1
python3 -m zipfile -c "$BASEDIR/support.zip" . > /dev/null 2>&1
cd - > /dev/null

# Cleanup
rm -rf "$WORKDIR"
rm -f "$TMPDIR/messages.log"
rm -f "$BASEDIR/support.log"

# Final move
if [ -f "$BASEDIR/support.zip" ]; then
    mv "$BASEDIR/support.zip" "$BASEDIR/printer_data/config/"
    echo "Upload the support.zip to discord"
else
    echo "ERROR: Failed to create the support.zip file"
fi
