#!/bin/sh

export TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE=/usr/data/printer_data/logs/switch-to-stock-$TIMESTAMP.log

# we are stopping klipper in this script so we want it to run even when klipper dies
nohup setsid /usr/data/pellcorp/k1/switch-to-stock.sh $1 </dev/null > $LOG_FILE 2>&1 &
