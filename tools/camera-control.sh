#!/bin/sh

control=
value=
for arg in "$@"; do
  case "$arg" in
    CONTROL=*) control=${arg#CONTROL=} ;;
    VALUE=*) value=${arg#VALUE=} ;;
  esac
done

device=$(v4l2-ctl --list-devices | grep -A1 usb | sed 's/^[[:space:]]*//g' | grep '^/dev' | head -1)
if [ -z "$device" ]; then
  echo "ERROR: No webcams found!"
  exit 1
fi

# no control just list the available controls and their current values
if [ -z "$control" ]; then
  controls=$(v4l2-ctl -d "$device" -L) || exit $?
  printf '%s\n' "$controls" | awk '
    /^[[:space:]]*[[:alnum:]_]+[[:space:]]+0x[[:xdigit:]]+[[:space:]]+\([^)]*\)[[:space:]]*:/ {
      if (menu_name != "") {
        if (options != "")
          print menu_name " (menu): options=[" options "] " menu_details
        else
          print menu_name " (menu): " menu_details
      }

      line = $0
      sub(/^[[:space:]]*/, "", line)
      name = line
      sub(/[[:space:]].*$/, "", name)
      type = line
      sub(/^[^(]*\(/, "", type)
      sub(/\).*/, "", type)
      details = line
      sub(/^[^:]*:[[:space:]]*/, "", details)

      min_value = ""
      max_value = ""
      if (match(details, /min=-?[0-9]+/))
        min_value = substr(details, RSTART + 4, RLENGTH - 4)
      if (match(details, /max=-?[0-9]+/))
        max_value = substr(details, RSTART + 4, RLENGTH - 4)
      if (match(details, /default=-?[0-9]+/)) {
        default_value = substr(details, RSTART + 8, RLENGTH - 8)
        if (min_value != "" && default_value + 0 < min_value + 0)
          details = substr(details, 1, RSTART + 7) min_value substr(details, RSTART + RLENGTH)
        else if (max_value != "" && default_value + 0 > max_value + 0)
          details = substr(details, 1, RSTART + 7) max_value substr(details, RSTART + RLENGTH)
      }

      options = ""
      menu_name = ""
      menu_details = ""
      if (type == "menu") {
        sub(/min=-?[0-9]+[[:space:]]+max=-?[0-9]+[[:space:]]*/, "", details)
        menu_name = name
        menu_details = details
      } else {
        print name " (" type "): " details
      }
      next
    }

    menu_name != "" && /^[[:space:]]*[0-9]+:/ {
      option = $0
      sub(/^[[:space:]]*/, "", option)
      if (options == "")
        options = option
      else
        options = options ", " option
      next
    }

    END {
      if (menu_name != "") {
        if (options != "")
          print menu_name " (menu): options=[" options "] " menu_details
        else
          print menu_name " (menu): " menu_details
      }
    }
  '
  exit $?
fi

if [ -z "$value" ]; then
  echo "ERROR: VALUE must be specified for CONTROL=$control"
  exit 1
fi

info=$(v4l2-ctl -d $device -l | grep "^[[:space:]]*$control " | head -1)
if [ -z "$info" ]; then
  echo "ERROR: Invalid control $control"
  exit 1
fi

requested=$value
if [ "$value" = "default" ]; then
  value=$(echo "$info" | sed -n 's/.*default=\([-0-9]*\).*/\1/p')
fi

case "$value" in
  ''|-|*[!0-9-]*|?*-*)
    echo "ERROR: Invalid value $value for $control"
    exit 1
    ;;
esac

if echo "$info" | grep -q "(bool)" && [ "$value" != "0" ] && [ "$value" != "1" ]; then
  echo "ERROR: Value $value for $control must be 0 or 1"
  exit 1
fi

min=$(echo "$info" | sed -n 's/.*min=\([-0-9]*\).*/\1/p')
max=$(echo "$info" | sed -n 's/.*max=\([-0-9]*\).*/\1/p')
if [ "$requested" = "default" ]; then
  if [ -n "$min" ] && [ "$value" -lt "$min" ]; then
    value=$min
  elif [ -n "$max" ] && [ "$value" -gt "$max" ]; then
    value=$max
  fi
fi
if [ -n "$min" ] && [ "$value" -lt "$min" ]; then
  echo "ERROR: Value $value for $control is below the minimum of $min"
  exit 1
fi
if [ -n "$max" ] && [ "$value" -gt "$max" ]; then
  echo "ERROR: Value $value for $control is above the maximum of $max"
  exit 1
fi

v4l2-ctl -d $device --set-ctrl $control=$value || exit 1
echo "INFO: Set $control to $value"

BASEDIR=$HOME
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi
CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"
WEBCAM_INI=$BASEDIR/printer_data/config/webcam.ini

# save to the webcam.ini [controls] section so the webcam service re-applies it on startup, a default
# value removes it, the section is created at the end of the file the first time a control is saved
if [ -f $WEBCAM_INI ]; then
  if [ "$requested" = "default" ]; then
    $CONFIG_HELPER --file $WEBCAM_INI --remove-section-entry controls $control || exit $?
  elif $CONFIG_HELPER --file $WEBCAM_INI --section-exists controls; then
    $CONFIG_HELPER --file $WEBCAM_INI --replace-section-entry controls $control $value || exit $?
  else
    [ -n "$(tail -c 1 $WEBCAM_INI)" ] && echo >> $WEBCAM_INI
    printf '\n[controls]\n%s: %s\n' "$control" "$value" >> $WEBCAM_INI
  fi
fi
