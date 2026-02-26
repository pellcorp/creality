#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi
# special helper just for the save config section
SAVE_CONFIG_HELPER="$BASEDIR/pellcorp/tools/save-config-helper.py"

probe=$1
if [ -z "$probe" ]; then
  exit 0
fi

if [ "$probe" = "cartotouch" ]; then
  $SAVE_CONFIG_HELPER --remove-section 'scanner*' 'axis_twist_compensation' 'bed_mesh*'
elif [ "$probe" = "btteddy" ]; then
  $SAVE_CONFIG_HELPER --remove-section 'probe_eddy_current*' 'temperature_probe btt_eddy' 'axis_twist_compensation' 'bed_mesh*'
elif [ "$probe" = "eddyng" ]; then
  $SAVE_CONFIG_HELPER --remove-section 'probe_eddy_ng*' 'axis_twist_compensation' 'bed_mesh*'
elif [ "$probe" = "beacon" ]; then
  $SAVE_CONFIG_HELPER --remove-section 'beacon*' 'axis_twist_compensation' 'bed_mesh*'
elif [ "$probe" = "cartographer" ]; then
  $SAVE_CONFIG_HELPER --remove-section 'cartographer*' 'axis_twist_compensation' 'bed_mesh*'
elif [ "$probe" = "microprobe" ] || [ "$probe" = "klicky" ]; then
  $SAVE_CONFIG_HELPER --remove-section 'probe' 'axis_twist_compensation' 'bed_mesh*'
elif [ "$probe" = "bltouch" ]; then
  $SAVE_CONFIG_HELPER --remove-section 'bltouch' 'axis_twist_compensation' 'bed_mesh*'
fi
