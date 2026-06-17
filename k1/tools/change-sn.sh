#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 <model> <structure_version>"
  echo "Models: CR-K1, K1C, K1 SE, CR-K1 Max, F001, F002, F004, F005, Nebula Pad"
  echo "Example: $0 'K1 SE' 1"
  exit 1
}

[ "$#" -eq 2 ] || usage

NEW_MODEL="$1"
NEW_STRUCTURE_VERSION="$2"

BLK_NUM="$(fdisk -l | grep 'sn_mac' | awk '{print $1}')"
[ -n "$BLK_NUM" ] || { echo "sn_mac partition not found"; exit 1; }

BLK="/dev/mmcblk0p${BLK_NUM}"
[ -b "$BLK" ] || { echo "not a block device: $BLK"; exit 1; }

RAW="$(dd if="$BLK" bs=512 count=1 2>/dev/null | tr -d '\000')"

MODEL="$(echo "$RAW" | awk -F';' '{print $3}')"
BOARD="$(echo "$RAW" | awk -F';' '{print $4}')"
SN="$(echo "$RAW" | awk -F';' '{print $1}')"
MAC="$(echo "$RAW" | awk -F';' '{print $2}')"
PCBA_TEST="$(echo "$RAW" | awk -F';' '{print $5}')"
MACHINE_SN="$(echo "$RAW" | awk -F';' '{print $6}')"
STRUCTURE_VERSION="$(echo "$RAW" | awk -F';' '{print $7}')"

echo "$SN" | grep -Eq '^[0-9A-Fa-f]{14}$' || { echo "existing SN is invalid; refusing"; exit 1; }
echo "$MAC" | grep -Eq '^[0-9A-Fa-f]{12}$' || { echo "existing MAC is invalid; refusing"; exit 1; }

case $BOARD in
  "CR4CU220812S10" | "CR4CU220812S11" | "CR4CU220812S12")
    case "$NEW_MODEL" in
      "CR-K1"|"K1C"|"K1 SE"|"CR-K1 Max"|"F001"|"F002") ;;
      *) echo "Unsupported model: $NEW_MODEL"; usage ;;
    esac
    ;;
  "NEBULA V1.0.0.1")
    case "$NEW_MODEL" in
      "F004"|"F005"|"Nebula Pad") ;;
      *) echo "Unsupported model: $NEW_MODEL"; usage ;;
    esac
    ;;
  *) echo "Unsupported board: $BOARD"; exit 1 ;;
esac

case "$NEW_STRUCTURE_VERSION" in
  0|1) ;;
  *) echo "structure_version must be 0 or 1"; exit 1 ;;
esac

if [ "$MODEL" != "$NEW_MODEL" ] || [ "$STRUCTURE_VERSION" != "$NEW_STRUCTURE_VERSION" ]; then
  NEW_RECORD="${SN};${MAC};${NEW_MODEL};${BOARD};${PCBA_TEST};${MACHINE_SN};${NEW_STRUCTURE_VERSION};;"

  [ "${#NEW_RECORD}" -lt 512 ] || { echo "new record too large"; exit 1; }

  BACKUP="/usr/data/sn_mac.$(date +%Y%m%d-%H%M%S).img"
  dd if="$BLK" of="$BACKUP" bs=512 count=1 2>/dev/null

  echo "backup: $BACKUP"
  echo "old: $RAW"
  echo "new: $NEW_RECORD"

  dd if=/dev/zero of="$BLK" bs=512 count=1 conv=notrunc 2>/dev/null
  printf '%s' "$NEW_RECORD" | dd of="$BLK" bs=1 conv=notrunc 2>/dev/null
  sync

  model=$(/usr/bin/get_sn_mac.sh model)
  structure_version=$(/usr/bin/get_sn_mac.sh structure_version)

  echo "Model is now $model"
  echo "Structure Version is now $structure_version"
else
  echo "Model is already $MODEL, Structure Version is already $STRUCTURE_VERSION"
fi
