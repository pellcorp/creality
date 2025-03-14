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

echo "Generating support.zip, please wait..."

if [ -f /usr/data/printer_data/config/support.tar.gz ]; then
    rm /usr/data/printer_data/config/support.tar.gz
fi
if [ -f /usr/data/support.zip ]; then
    rm /usr/data/support.zip
fi
if [ -f /usr/data/printer_data/config/support.zip ]; then
    rm /usr/data/printer_data/config/support.zip
fi

if [ -f /usr/data/support.log ]; then
    rm /usr/data/support.log
fi

DATE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
echo "----------------------------------------------------------------------------" >> /usr/data/support.log
echo "Simple AF installation details ${DATE_TIME}" >> /usr/data/support.log
echo "---------------- top -------------------------------------------------------" >> /usr/data/support.log
top -b -n 1 >> /usr/data/support.log
echo "---------------- free ------------------------------------------------------" >> /usr/data/support.log
free >> /usr/data/support.log
echo "---------------- lsusb -----------------------------------------------------" >> /usr/data/support.log
lsusb >> /usr/data/support.log
echo "---------------- ls -la /etc/init.d ----------------------------------------" >> /usr/data/support.log
ls -la /etc/init.d >> /usr/data/support.log
echo "---------------- ls -laR /usr/data -----------------------------------------" >> /usr/data/support.log
ls -laR /usr/data >> /usr/data/support.log
echo "----------------------------------------------------------------------------" >> /usr/data/support.log

cd /usr/data
python3 -m zipfile -c /usr/data/support.zip support.log pellcorp-overrides/ pellcorp-backups/ printer_data/config/ printer_data/logs/installer-*.log printer_data/logs/klippy.log printer_data/logs/moonraker.log printer_data/logs/guppyscreen.log /var/log/messages 2> /dev/null
cd - > /dev/null

rm /usr/data/support.log
if [ -f /usr/data/support.zip ]; then
    mv /usr/data/support.zip /usr/data/printer_data/config/
    echo "Upload the support.zip to discord"
else
    echo "ERROR: Failed to create the support.zip file"
fi
