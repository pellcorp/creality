#!/bin/bash

if grep -Fqs "ID=buildroot" /etc/os-release; then
  echo "FATAL: This is a tool to run on a desktop to generate clean base cfg files"
  exit 1
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
K1_DIR=$(dirname $CURRENT_DIR)
CREALITY_DIR=$(dirname $K1_DIR)
ROOT_DIR=$(dirname $CREALITY_DIR)

CONFIG_DIR=$ROOT_DIR/creality-firmware/configs/usr/share/klipper/config/
if [ ! -d $CONFIG_DIR ]; then
  echo "Missing $ROOT_DIR/creality-firmware/configs/usr/share/klipper/config/"
  exit 1
fi

python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
if [ $? -ne 0 ]; then
  echo "ERROR: configupdater python module not available"
  echo "Try:"
  echo "  python3 -m venv $ROOT_DIR/.venv"
  echo "  source $ROOT_DIR/.venv/bin/activate"
  echo "  pip install $CREALITY_DIR/packages/ConfigUpdater-3.2-py2.py3-none-any.whl"
  exit 1
fi

export BASEDIR=$CREALITY_DIR

function cleanup_printer_cfg() {
  local source=$1
  local target=$2
  local model=$3

  if [ ! -f $CONFIG_DIR/$source/printer.cfg ]; then
    echo "Failed to find $CONFIG_DIR/$source/printer.cfg"
    exit 1
  fi

  echo "Creating $target ..."
  cp $CONFIG_DIR/$source/printer.cfg $CREALITY_DIR/k1/printers/$target

  # just in case remove any save config that might have snuck in
  sed -i '/#\*#.*/d' $CREALITY_DIR/k1/printers/$target

  MODEL=$model $CREALITY_DIR/k1/tools/cleanup-printer-cfg.sh $CREALITY_DIR/k1/printers/$target

  # remove duplicate new lines
  awk 'NF { blank=0 } !NF { if (blank++) next } { print }' $CREALITY_DIR/k1/printers/$target > /tmp/printer.cfg.$$
  mv /tmp/printer.cfg.$$ $CREALITY_DIR/k1/printers/$target

  # remove comments at ends of lines
  sed -i -E 's/([^[:space:]])[[:space:]]*#.*/\1/' $CREALITY_DIR/k1/printers/$target

  perl -CSDA -i -ne 'print unless /^\s*#.*\p{Han}/' $CREALITY_DIR/k1/printers/$target

  if [ "$source" = "F004" ]; then
    sed -i 's/CR-10 SE/Ender 5 Max/g' $CREALITY_DIR/k1/printers/$target
  elif [ "$model" = "K1 SE" ]; then
    sed -i 's/K1C/K1 SE/g' $CREALITY_DIR/k1/printers/$target
  fi
}

cleanup_printer_cfg K1_CR4CU220812S12 k1-2023.cfg "CR-K1"
cleanup_printer_cfg K1_CR4CU220812S12_1 k1-2024.cfg "CR-K1"
cleanup_printer_cfg K1_MAX_CR4CU220812S12 k1m-2023.cfg "CR-K1 Max"
cleanup_printer_cfg K1_MAX_CR4CU220812S12_1 k1m-2024.cfg "CR-K1 Max"
cleanup_printer_cfg K1C_CR4CU220812S12 k1c.cfg "K1C"
cleanup_printer_cfg K1_SE_CR4CU220812S12 k1se.cfg "K1 SE"
cleanup_printer_cfg F001 e3v3.cfg "F001"
cleanup_printer_cfg F002 e3v3-plus.cfg "F002"
cleanup_printer_cfg F003 cr10se.cfg "F003"
cleanup_printer_cfg F004 ender5max.cfg "F004"
cleanup_printer_cfg F005 e3v3ke.cfg "F005"
