#!/bin/bash

BASEDIR=$HOME

# initially this is just USB automount at some point we might add the wifi stuff
sudo ln -sf $BASEDIR/pellcorp/rpi/etc/automount /etc
sudo cp $BASEDIR/pellcorp/rpi/etc/systemd/system/usb-mount\@.service /etc/systemd/system/
sudo cp $BASEDIR/pellcorp/rpi/etc/udev/rules.d/99-automount.rules /etc/udev/rules.d/
sudo systemctl daemon-reload
