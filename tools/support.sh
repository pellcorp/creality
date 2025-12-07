#!/bin/sh

BASEDIR=$HOME
TMPDIR=/tmp
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
    TMPDIR=$BASEDIR/tmp

    mkdir -p $TMPDIR
    
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
else
  # on rpi should not be run as root
  if [ "$(whoami)" = "root" ]; then
    echo "FATAL: This installer must not be run as root"
    exit 1
  fi
fi

echo
echo "INFO: Generating support.zip, please wait..."

if [ -f $BASEDIR/printer_data/config/support.tar.gz ]; then
    rm $BASEDIR/printer_data/config/support.tar.gz
fi
if [ -f $BASEDIR/support.zip ]; then
    rm $BASEDIR/support.zip
fi
if [ -f $BASEDIR/printer_data/config/support.zip ]; then
    rm $BASEDIR/printer_data/config/support.zip
fi

if [ -f $BASEDIR/support.log ]; then
    rm $BASEDIR/support.log
fi

DATE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
echo "----------------------------------------------------------------------------" >> $BASEDIR/support.log
echo "Simple AF installation details ${DATE_TIME}" >> $BASEDIR/support.log
echo "---------------- top -------------------------------------------------------" >> $BASEDIR/support.log
top -b -n 1 >> $BASEDIR/support.log
echo "---------------- free ------------------------------------------------------" >> $BASEDIR/support.log
free >> $BASEDIR/support.log
command -v lsusb > /dev/null
if [ $? -eq 0 ]; then
  echo "---------------- lsusb -----------------------------------------------------" >> $BASEDIR/support.log
  lsusb >> $BASEDIR/support.log
fi
if [ -d /etc/init.d ]; then
  echo "---------------- ls -la /etc/init.d ----------------------------------------" >> $BASEDIR/support.log
  ls -la /etc/init.d >> $BASEDIR/support.log
fi

echo "---------------- ls -laR $BASEDIR -----------------------------------------" >> $BASEDIR/support.log
ls -laR $BASEDIR 2> /dev/null >> $BASEDIR/support.log
echo "----------------------------------------------------------------------------" >> $BASEDIR/support.log

if [ -f /var/log/messages ]; then
    cat /var/log/messages > $TMPDIR/messages.log
else
    sudo journalctl --dmesg > $TMPDIR/messages.log
fi

cd $BASEDIR

latest_klippy_log=$(ls -Art printer_data/logs/klippy.log.* 2>/dev/null | tail -n 1)
if [ -z "$latest_klippy_log" ] || [ ! -f $latest_klippy_log ]; then
  unset latest_klippy_log
fi

$BASEDIR/pellcorp/tools/supportzip.py $BASEDIR/support.zip support.log pellcorp-overrides/ pellcorp-backups/ printer_data/config/ printer_data/logs/installer-*.log printer_data/logs/klippy.log $latest_klippy_log printer_data/logs/moonraker.log printer_data/logs/grumpyscreen.log $TMPDIR/messages.log /tmp/mcu_update.log
cd - > /dev/null

rm $TMPDIR/messages.log
rm $BASEDIR/support.log
if [ -f $BASEDIR/support.zip ]; then
    mv $BASEDIR/support.zip $BASEDIR/printer_data/config/
    echo
    echo "Upload the $BASEDIR/printer_data/config/support.zip to discord"
    echo "You can also find it in the config directory in fluidd or mainsail"
    echo
    exit 0
else
    echo "ERROR: Failed to create the support.zip file"
    exit 1
fi
