#!/bin/bash
# shamelessly copied from https://github.com/k1-debian/

ACTION=$1
DEVBASE=$2
DEVICE="/dev/${DEVBASE}"

# See if this drive is already mounted
MOUNT_POINT=$(/bin/mount | /bin/grep ${DEVICE} | /usr/bin/awk '{ print $3 }')

do_mount() {
  if [[ -n ${MOUNT_POINT} ]]; then
    # Already mounted, exit
    exit 1
  fi

  MOUNT_POINT="/media/usb"

  /bin/mkdir -p ${MOUNT_POINT}

  # Global mount options
  OPTS="ro,relatime"

  # File system type specific mount options
  if [[ ${ID_FS_TYPE} == "vfat" ]]; then
    OPTS+=",user,uid=1000,gid=1000,umask=000,shortname=mixed,utf8=1,flush"
  fi

  if ! /bin/mount -o ${OPTS} ${DEVICE} ${MOUNT_POINT}; then
    exit 1
  fi
}

do_unmount() {
  if [[ -n ${MOUNT_POINT} ]]; then
    /bin/umount -l ${DEVICE}
  fi
}
case "${ACTION}" in
  add)
    do_mount
    ;;
  remove)
    do_unmount
    ;;
esac
