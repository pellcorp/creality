#!/bin/sh

CONFIG_HELPER="/usr/data/pellcorp/k1/config-helper.py"

MODEL=$(/usr/bin/get_sn_mac.sh model)
if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ] || [ "$MODEL" = "K1 SE" ]; then
  model=k1
elif [ "$MODEL" = "CR-K1 Max" ] || [ "$MODEL" = "K1 Max SE" ]; then
  model=k1m
else
  echo "This script is not supported for $MODEL!"
  exit 1
fi

function apply_mount_overrides() {
  local probe=$1
  local mount=$2

  return_status=0
  overrides_dir=/usr/data/pellcorp/k1/mounts/$probe/$mount
  if [ ! -d /usr/data/pellcorp/k1/mounts/$probe/$mount ]; then
    echo "ERROR: Probe and Mount combination not found"
    exit 0 # FIXME unfortunately we are using this exit code to know overrides were applied
  fi

  files=$(find $overrides_dir -maxdepth 1 -name "*.cfg")
  for file in $files; do
      file=$(basename $file)

      # special case for cartotouch
      if [ "$file" = "cartographer.cfg" ] && [ "$probe" = "cartographer" ]; then
        target_file=cartotouch.cfg
      elif [ "$file" = "bltouch.cfg" ] && [ "$probe" = "bltouch" ]; then # bltouch.cfg is merged into printer.cfg
        target_file=printer.cfg
      elif [ "$file" = "microprobe.cfg" ] && [ "$probe" = "microprobe" ]; then # microprobe.cfg is merged into printer.cfg
        target_file=printer.cfg
      else
        target_file=$(echo "$name" | sed "s/-$model//g")
      fi

      if [ -f /usr/data/printer_data/config/$target_file ]; then
        echo "Applying $overrides_dir/$file to $target_file ..."
        $CONFIG_HELPER --file $target_file --overrides $overrides_dir/$file || exit $?
      else
        echo "Ignoring overrides for missing /usr/data/printer_data/config/$target_file"
      fi
      return_status=1
  done
  sync
  return $return_status
}

mode=config
if [ "$1" = "--verify" ]; then
  mode=verify
  shift
fi

# note for cartotouch we pass in 'cartographer' as the mount
if [ $# -ne 2 ]; then
  echo "Usage: $0 <cartographer|btteddy|microprobe|bltouch> <mount>"
  exit 0
fi

probe=$1
mount=$2

if [ "$probe" = "cartotouch" ]; then
  probe=cartographer
fi

if [ "$mode" = "verify" ]; then
  if [ -d /usr/data/pellcorp/k1/mounts/$probe ]; then
    if [ -d /usr/data/pellcorp/k1/mounts/$probe/$mount ]; then
      exit 0
    else
      echo "ERROR: Invalid $probe mount $mount specified!"
      echo "The following mounts are available:"
      ls /usr/data/pellcorp/k1/mounts/$probe | tr ' ' '\n'
      echo
      exit 1
    fi
  else
    echo "ERROR: Invalid probe $probe specified!"
    exit 1
  fi
else
  apply_mount_overrides "$probe" "$mount"
fi
