#!/bin/sh

set -eu

board=$(/usr/bin/get_sn_mac.sh board)
model=$(get_sn_mac.sh model)

EXPECTED_RTOS_SIZE=$((4 * 1024 * 1024))
SCRIPT_NAME=${0##*/}

die() {
    echo "Error: $*" >&2
    exit 1
}

assume_yes=0
if [ "${1:-}" = "--yes" ]; then
    assume_yes=1
    shift
fi

# I have concerns that trying to do this for Ender 5 Max or Ender 3 V3 might cause issues
image=
if [ "$board" = "CR4CU220812S11" ]  || [ "$board" = "CR4CU220812S12" ]; then
  if [ "$model" = "CR-K1" ] || [ "$model" = "K1C" ] || [ "$model" = "K1 SE" ] || [ "$model" = "CR-K1 Max" ]; then
    image=/usr/data/pellcorp/k1/zero/zero-k1.bin
  else
    echo "FATAL: Board model $model not supported!"
    exit 1
  fi
elif [ "$board" = "NEBULA V1.0.0.1" ]; then
  if [ "$model" = "F005" ] || [ "$model" = "F003" ]; then
    image=/usr/data/pellcorp/k1/zero/zero-nebula.bin
  else
    echo "FATAL: Board model $model not supported!"
    exit 1
  fi
else
  echo "FATAL: Board $board not supported"
  exit 1
fi

# this is just as a handy catch for me when testing to make sure I am writing the correct image
image_size=$(wc -c < "$image")
case "$image_size" in
    432824) model_name='Nebula Pad' ;;
    452408) model_name='K1' ;;
    *) die "Unsupported zero.bin size: $image_size bytes." ;;
esac

grep -aq 'application_boot_logo' "$image" || \
    die "This does not look like the expected $model_name zero.bin (logo code missing)."

if [ -e /dev/disk/by-partlabel/rtos ]; then
    target=$(readlink -f /dev/disk/by-partlabel/rtos)
else
    [ -r /etc/ota_bin/ota_utils.sh ] || die "Cannot find the rtos partition helper."
    # This is the same resolver used by Creality's OTA scripts.
    . /etc/ota_bin/ota_utils.sh
    target=$(mmc_name_to_dev rtos)
fi

[ -n "$target" ] && [ -b "$target" ] || die "Could not resolve the rtos block device."
# Linux exposes the partition size here as a count of 512-byte sectors.
sector_file=/sys/class/block/${target##*/}/size
[ -r "$sector_file" ] || die "Cannot determine partition size for $target."
target_size=$(( $(cat "$sector_file") * 512 ))
[ "$target_size" -eq "$EXPECTED_RTOS_SIZE" ] || \
    die "Expected a 4 MiB rtos partition; $target is $target_size bytes."

image_md5=$(md5sum "$image" | awk '{print $1}')
target_md5=$(dd if="$target" bs=1 count="$image_size" 2>/dev/null | md5sum | awk '{print $1}')
if [ "$image_md5" = "$target_md5" ]; then
    echo "The rtos partition already matches $image; nothing written."
    exit 0
fi

backup="/usr/data/$(basename ${image}).rtos-backup.bin"
[ ! -e "$backup" ] || die "Refusing to overwrite existing backup: $backup"

echo "Model:  $model_name"
echo "Image:  $image ($image_size bytes)"
echo "Target: $target ($target_size bytes, GPT label rtos)"
echo "Backup: $backup"
echo "Writing replaces the early boot RTOS/logo."
if [ "$assume_yes" -ne 1 ]; then
    printf 'Type WRITE-RTOS to continue: '
    read answer
    [ "$answer" = "WRITE-RTOS" ] || die "Cancelled."
fi

echo "Backing up current RTOS partition..."
dd if="$target" of="$backup" bs=1M
sync
[ "$(wc -c < "$backup")" -eq "$EXPECTED_RTOS_SIZE" ] || die "Backup size check failed."

echo "Writing patched $model_name zero.bin..."
dd if="$image" of="$target" bs=1M
sync

written_md5=$(dd if="$target" bs=1 count="$image_size" 2>/dev/null | md5sum | awk '{print $1}')
[ "$written_md5" = "$image_md5" ] || die "Verification failed; do not reboot."

echo "Success. The RTOS partition matches the supplied $model_name zero.bin."
echo "Backup retained at: $backup"
