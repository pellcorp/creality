#!/bin/sh

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi
# special helper just for the save config section
SAVE_CONFIG_HELPER="$BASEDIR/pellcorp/tools/save-config-helper.py"
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"

probe=$1
if [ -z "$probe" ]; then
  exit 0
fi

switch=probe
# if switch is mount we behave slightly differently
if [ "$2" = "--mount" ]; then
  switch=mount
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

  # for switching a mount we want a default z_offset restored
  if [ "$switch" = "mount" ]; then
    $CONFIG_HELPER --remove-section "probe" || exit $?
    $CONFIG_HELPER --add-section "probe" || exit $?
    $CONFIG_HELPER --replace-section-entry "probe" "z_offset" "0.0" || exit $?
  fi
elif [ "$probe" = "bltouch" ]; then
  $SAVE_CONFIG_HELPER --remove-section 'bltouch' 'axis_twist_compensation' 'bed_mesh*'

  # for switching a mount we want a default z_offset restored
  if [ "$switch" = "mount" ]; then
    $CONFIG_HELPER --remove-section "bltouch" || exit $?
    $CONFIG_HELPER --add-section "bltouch" || exit $?
    $CONFIG_HELPER --replace-section-entry "bltouch" "z_offset" "0.0"
  fi
fi
