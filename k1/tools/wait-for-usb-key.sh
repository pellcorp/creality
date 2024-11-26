#!/bin/sh

echo "Waiting for USB Key ..."
while true; do
  mounted=$(mount | grep /tmp/udisk/sda)
  if [ $? -eq 0 ]; then
    mount=$(echo "$mounted" | awk '{print $3}')
    if [ "$mount" = "/tmp/udisk/sda1" ]; then
      echo
      echo "INFO - USB Key was recognised and mounted correctly ($mount)"
      umount $mount
      break
    else
      echo
      echo "WARNING: USB Key was recognised and mounted correctly but on a different mount point ($mount)"
      umount $mount
      break
    fi
  fi
  sleep 0.5s
done
