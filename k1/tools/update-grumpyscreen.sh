#!/bin/sh

MODEL=$(/usr/bin/get_sn_mac.sh model)
if [ "$MODEL" = "Nebula Pad" ]; then
  MODEL=NEBULA
fi

asset_name=grumpyscreen.tar.gz
# Ender 5 Max, Ender 3 V3 KE and CR10SE have a Nebula Pad which is small resolution
if [ "$MODEL" = "F003" ] || [ "$MODEL" = "F004" ] || [ "$MODEL" = "F005" ] || [ "$MODEL" = "NEBULA" ]; then
    asset_name=grumpyscreen-smallscreen.tar.gz
fi

CONFIG_HELPER="/usr/data/pellcorp/tools/config-helper.py"

# stolen from https://github.com/lavabit/robox/
function retry() {
  local COUNT=1
  local DELAY=0
  local RESULT=0
  while [[ "${COUNT}" -le 10 ]]; do
    [[ "${RESULT}" -ne 0 ]] && {
      echo -e "\n${*} failed... retrying ${COUNT} of 10.\n" >&2
    }
    "${@}" && { RESULT=0 && break; } || RESULT="${?}"
    COUNT="$((COUNT + 1))"

    # Increase the delay with each iteration.
    DELAY="$((DELAY + 10))"
    sleep $DELAY
  done

  [[ "${COUNT}" -gt 10 ]] && {
    echo -e "\nThe command failed 10 times.\n" >&2
  }

  return "${RESULT}"
}

if [ ! -f /usr/data/grumpyscreen/grumpyscreen ] || [ ! -f /usr/data/grumpyscreen/grumpyscreen.cfg ] || [ ! -f /etc/init.d/S99grumpyscreen ]; then
  echo "FATAL: Existing grumpyscreen installation required"
  exit 1
elif [ ! -f /usr/data/printer_data/config/grumpyscreen.ini ]; then
  echo "FATAL: Existing grumpyscreen installation is too old"
  exit 1
fi

if [ "$1" != "-f" ]; then
  echo "FATAL: Update grumpyscreen does not backup your existing installation of grumpyscreen!"
  echo "It will overwrite:"
  echo "- /usr/data/grumpyscreen/grumpyscreen"
  echo "- /usr/data/grumpyscreen/grumpyscreen.cfg"
  echo "- /usr/data/grumpyscreen/release.info"
  echo "If you are ok with that add the -f argument to the update-grumpyscreen.sh command to update!"
  exit 1
fi

echo "INFO: Updating grumpyscreen ..."

/etc/init.d/S99grumpyscreen stop > /dev/null 2>&1
killall -q guppyscreen > /dev/null 2>&1

retry curl -L "https://github.com/pellcorp/grumpyscreen/releases/download/main/${asset_name}" -o /usr/data/grumpyscreen.tar.gz || exit $?
tar xf /usr/data/grumpyscreen.tar.gz -C /usr/data/ 2> /dev/null || exit $?
rm /usr/data/grumpyscreen.tar.gz

echo
echo "INFO: Updating grumpyscreen config ..."

# for Ender 5 Max we want display_rotate: 2 and that gets set by grumpyscreen package
# so we need to switch it to 0 for KE and Nebula
if [ "$MODEL" = "F003" ] || [ "$MODEL" = "F005" ] || [ "$MODEL" = "NEBULA" ]; then
  sed -i "s/display_rotate:.*/display_rotate: 0/g" /usr/data/grumpyscreen/grumpyscreen.cfg
fi

# switch to stock makes no sense for nebula because we are starting with base firmware with no stock mode
if [ "$MODEL" = "NEBULA" ]; then
  sed -i "s/switch_to_stock_cmd:.*/switch_to_stock_cmd:/g" /usr/data/grumpyscreen/grumpyscreen.cfg
fi

kinematics=$($CONFIG_HELPER --get-section-entry "printer" "kinematics")
if [ "$kinematics" = "cartesian" ]; then
  $CONFIG_HELPER --file /usr/data/grumpyscreen/grumpyscreen.cfg --replace-section-entry "ui" "invert_z_icon" "true" || exit $?
fi

/etc/init.d/S99grumpyscreen start > /dev/null 2>&1
