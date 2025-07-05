#!/bin/bash

BASEDIR=$HOME
source $BASEDIR/pellcorp/rpi/functions.sh
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
mode=apply

function verify_printer_file() {
  local printer_cfg=$1

  # for a arbitrary file we want to validate it was downloaded correctly
  kinematics=$($CONFIG_HELPER --file $printer_cfg --get-section-entry "printer" "kinematics" --default-value unknown 2> /dev/null)

  valid_printer=true

  # for now only support cartesian and corexy
  if [ "$kinematics" != "cartesian" ] && [ "$kinematics" != "corexy" ]; then
    echo "ERROR: Invalid printer configuration file - kinematics not supported ($kinematics)"
    valid_printer=false
  fi

  if ! $CONFIG_HELPER --file $printer_cfg --section-exists "extruder"; then
    echo "ERROR: Invalid printer configuration file - extruder is not defined"
    valid_printer=false
  fi

  valid_fans=false
  if $CONFIG_HELPER --file $printer_cfg --section-exists "fan"; then
    valid_fans=true
  elif $CONFIG_HELPER --file $printer_cfg --section-exists "fan_generic part"; then
    valid_fans=true
  fi
  if [ "$valid_fans" != "true" ]; then
    echo "ERROR: Invalid printer configuration file - a fan or generic_fan must be defined"
    valid_printer=false
  fi

  if ! $CONFIG_HELPER --file $printer_cfg --section-exists "stepper_x"; then
    echo "ERROR: Invalid printer configuration file - stepper_x is not defined"
    valid_printer=false
  else
    value=$($CONFIG_HELPER --file $printer_cfg --get-section-entry "stepper_x" "position_max")
    if [ -z "$value" ]; then
      echo "ERROR: Invalid printer configuration file - stepper_x position_max is not defined"
      valid_printer=false
    fi
  fi

  if ! $CONFIG_HELPER --file $printer_cfg --section-exists "stepper_y"; then
    echo "ERROR: Invalid printer configuration file - stepper_y is not defined"
    valid_printer=false
  else
    value=$($CONFIG_HELPER --file $printer_cfg --get-section-entry "stepper_y" "position_max")
    if [ -z "$value" ]; then
      echo "ERROR: Invalid printer configuration file - stepper_y position_max is not defined"
      valid_printer=false
    fi
  fi

  if [ "$valid_printer" != "true" ]; then
    exit 1
  fi
}

if [ $# -eq 0 ]; then
  echo "Usage: $0 [--verify] <printer>"
  exit 1
fi

if [ "$1" = "--verify" ]; then
  mode=verify
  shift
fi
printer=$1

if [[ $printer =~ https?://* ]]; then
  filename=$(basename $printer)
  printer_cfg=$(realpath ~/$filename)
  if [ "$mode" = "verify" ]; then
    if [ ! -f $printer_cfg ]; then
      command -v wget > /dev/null
      if [ $? -ne 0 ]; then
          retry sudo apt-get install --yes wget; error
      fi
      printer=$(echo "$printer" | sed 's/github.com/raw.githubusercontent.com/g' | sed 's:blob:refs/heads:g')
      wget -q $printer -O /tmp/printer.cfg.$$ || exit $?
      # verify the downloaded file is a printer cfg file
      if grep -q "^\[printer]" /tmp/printer.cfg.$$; then
        mv /tmp/printer.cfg.$$ $printer_cfg
      else
        rm /tmp/printer.cfg.$$
        echo "ERROR: Invalid printer url specified - perhaps you need the raw download link!"
        exit 1
      fi
    else
      echo "INFO: $printer_cfg already downloaded"
    fi
    verify_printer_file $printer_cfg
  fi
elif [[ "$printer" == *\/* ]] && [ -f $printer ]; then
  printer_cfg=$(realpath $printer)
  if [ "$mode" = "verify" ]; then
    verify_printer_file $printer_cfg
  fi
elif [ -f "$BASEDIR/pellcorp/rpi/printers/${printer}.cfg" ]; then
  printer_cfg=$BASEDIR/pellcorp/rpi/printers/${printer}.cfg
else
  echo "ERROR: Invalid printer (${printer}) specified"
  if [ "$mode" = "verify" ]; then
    echo "The following printers are supported:"
    echo
    files=$(find $BASEDIR/pellcorp/rpi/printers -maxdepth 1 -name "*.cfg")
    for file in $files; do
      file=$(basename $file .cfg)
      comment=$(cat $BASEDIR/pellcorp/rpi/printers/${file}.cfg | grep "^#" | head -1 | sed 's/#\s*//g')
      echo "  * $file - $comment"
    done
  fi
  exit 1
fi

model=$(cat $printer_cfg | grep MODEL: | awk -F ':' '{print $2}')
if [ -z "$model" ]; then
  model=unspecified
fi

if [ "$mode" = "verify" ]; then
  exit 0
fi

# save a reference to what printer was chosen
echo "printer=$printer" > $BASEDIR/pellcorp-overrides/config.info

mkdir -p $BASEDIR/pellcorp-backups
rm $BASEDIR/pellcorp-backups/*.factory.cfg 2> /dev/null

if grep -q "^-- printer.cfg" $printer_cfg; then
  file=
  while IFS= read -r line; do
    if echo "$line" | grep -q "^--"; then
      file=$(echo $line | sed 's/-- //g' | sed 's/.cfg//g')
      if [ -n "$model" ] && [ "$file" = "printer" ] && [ ! -f $BASEDIR/pellcorp-backups/printer.factory.cfg ]; then
        echo "# MODEL:$model" > $BASEDIR/pellcorp-backups/printer.factory.cfg
      else
        touch $BASEDIR/pellcorp-backups/${file}.factory.cfg
      fi
    elif echo "$line" | grep -q "^#"; then
      continue # skip comments
    elif [ -n "$file" ] && [ -f $BASEDIR/pellcorp-backups/${file}.factory.cfg ]; then
      echo "$line" >> $BASEDIR/pellcorp-backups/${file}.factory.cfg
    fi
  done < "$printer_cfg"
else
  cp $printer_cfg $BASEDIR/pellcorp-backups/printer.factory.cfg
fi

if [ -f $BASEDIR/pellcorp-backups/printer.factory.cfg ]; then
  # cleanup the factory config file of all illegal config sections
  # fixme - perhaps we should have a white list instead of a black list
  $CONFIG_HELPER --file $BASEDIR/pellcorp-backups/printer.factory.cfg --remove-section "bltouch"
  $CONFIG_HELPER --file $BASEDIR/pellcorp-backups/printer.factory.cfg --remove-section "probe"
  $CONFIG_HELPER --file $BASEDIR/pellcorp-backups/printer.factory.cfg --remove-section "safe_z_home"
  $CONFIG_HELPER --file $BASEDIR/pellcorp-backups/printer.factory.cfg --remove-section "homing_override"
  $CONFIG_HELPER --file $BASEDIR/pellcorp-backups/printer.factory.cfg --remove-section "force_move"
  $CONFIG_HELPER --file $BASEDIR/pellcorp-backups/printer.factory.cfg --remove-section "pause_resume"

  exit 0
else
  echo "ERROR: Missing printer.cfg file"
  exit 1
fi
