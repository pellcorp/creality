#!/bin/sh

BASEDIR=/home/pi
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"

apply_mount_overrides() {
    local probe=$1
    local mount=$2
    local model=$3

    return_status=0
    overrides_dir=$BASEDIR/pellcorp/mounts/$probe/$mount
    if [ ! -f $BASEDIR/pellcorp/mounts/$probe/${mount}-${model}.overrides ]; then
        echo "ERROR: Probe (${probe}), Mount (${mount}) and Model (${model}) combination not found"
        exit 0 # FIXME unfortunately we are using this exit code to know overrides were applied
    fi

    echo
    echo "INFO: Applying mount ($mount) overrides ..."
    echo "WARNING: Please verify the mount configuration is correct before homing your printer, performing a bed mesh or using Screws Tilt Calculate"
    overrides_dir=/tmp/overrides.$$
    mkdir $overrides_dir
    file=
    while IFS= read -r line; do
        if echo "$line" | grep -q "^--"; then
            file=$(echo $line | sed 's/-- //g')
            touch $overrides_dir/$file
        elif echo "$line" | grep -q "^#"; then
            continue # skip comments
        elif [ -n "$file" ] && [ -f $overrides_dir/$file ]; then
            echo "$line" >> $overrides_dir/$file
        fi
    done < "$BASEDIR/pellcorp/mounts/$probe/${mount}-${model}.overrides"

  files=$(find $overrides_dir -maxdepth 1 -name "*.cfg")
  for file in $files; do
      file=$(basename $file)

      if [ -f $BASEDIR/printer_data/config/$file ]; then
          $CONFIG_HELPER --file $file --patches $overrides_dir/$file || exit $?
          return_status=1
      fi
  done
  rm -rf $overrides_dir
  sync
  return $return_status
}

restart_klipper=false

mode=config
if [ "$1" = "--verify" ]; then
    mode=verify
    shift
elif [ "$1" = "--restart" ]; then
  restart_klipper=true
  shift
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 [--verify] <cartotouch|btteddy|eddyng|microprobe|bltouch|beacon|klicky> <mount>"
    exit 0
fi

probe=$1
mount=$2
model=$3

if [ "$mode" = "verify" ]; then
    if [ -d $BASEDIR/pellcorp/mounts/$probe ]; then
        if [ -f $BASEDIR/pellcorp/mounts/$probe/${mount}-${model}.overrides ]; then
            exit 0
        else
            if [ -n "$mount" ]; then
                echo "ERROR: Invalid Probe (${probe}), Mount (${mount}) and Model (${model}) combination"
            fi
            echo
            echo "The following mounts are available:"
            echo

            if [ -f $BASEDIR/pellcorp/mounts/$probe/Default-${model}.overrides ]; then
                comment=$(cat $BASEDIR/pellcorp/mounts/$probe/Default-${model}.overrides | grep "^#" | head -1 | sed 's/#\s*//g')
                echo "  * Default - $comment"
            fi

            files=$(find $BASEDIR/pellcorp/mounts/$probe -maxdepth 1 -name "*-${model}.overrides")
            for file in $files; do
                comment=$(cat $file | grep "^#" | head -1 | sed 's/#\s*//g')
                file=$(basename $file .overrides | sed "s/-${model}//g")
                if [ "$file" != "Default" ]; then
                    echo "  * $file - $comment"
                fi
            done
            echo
            echo "WARNING: Please verify the mount configuration is correct before homing your printer, performing a bed mesh or using Screws Tilt Calculate"
            echo
            exit 1
        fi
      else
          echo "ERROR: Invalid probe $probe specified!"
          exit 1
      fi
else
    apply_mount_overrides "$probe" "$mount" "$model"
    status=$?
    if [ $status -ne 0 ] && [ "$restart_klipper" = "true" ]; then
      echo "INFO: Restarting Klipper ..."
      sudo systemctl restart klipper
    fi
    exit $status
fi
