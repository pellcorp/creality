#!/bin/bash

if [ "$(whoami)" = "root" ]; then
  echo "FATAL: This installer must not be run as root"
  exit 1
fi

BASEDIR=$HOME

command -v lsb_release > /dev/null
if [ $? -ne 0 ]; then
  retry sudo apt-get install -y lsb-release; error
fi

source $BASEDIR/pellcorp/rpi/functions.sh

CONFIG_HELPER="$BASEDIR/pellcorp/tools/config-helper.py"

# everything else in the script assumes its cloned to $BASEDIR/pellcorp
# so we must verify this or shit goes wrong
if [ "$(dirname $(readlink -f $0))" != "$BASEDIR/pellcorp/rpi" ]; then
  >&2 echo "ERROR: This git repo must be cloned to $BASEDIR/pellcorp/rpi"
  exit 1
fi

if [ -d $BASEDIR/kiauh ]; then
    echo "Simple AF is not compatible with kiuah"
    exit 1
fi

if [ -d $BASEDIR/printer_data/config/printer.cfg ] && [ ! -f $BASEDIR/pellcorp.done ]; then
    echo "Simple AF cannot be installed on a configured printer"
    exit 1
fi

command -v apt-get > /dev/null
if [ $? -ne 0 ]; then
  echo "FATAL: This OS does not appear to be debian based - aborting"
  exit 1
fi

sudo -k
sudo -n true 2>/dev/null
if [ $? -ne 0 ]; then
  echo "WARN: Sudo requires a password - attempting to fix, you will be prompted for the $USER password"
  sudo -n true 2>/dev/null
  echo "$USER ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/nopasswd > /dev/null
  sudo -n true 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "FATAL: Removing the requirement for sudo to provide a password failed"
    exit 1
  fi
fi

# stupid fucking orange pi broken since 2023
if [ -f /etc/apt/sources.list.d/docker.list ]; then
  sudo rm /etc/apt/sources.list.d/docker.list
fi

pi_model=0
if [ -e /proc/device-tree/model ]; then
    device_model=$(tr -d '\0' < /proc/device-tree/model)
    if [[ "$device_model" == *"Raspberry Pi 4"* ]]; then
      pi_model=4
    elif [[ "$device_model" == *"Raspberry Pi 5"* ]]; then
      pi_model=5
    elif [[ "$device_model" == *"Raspberry Pi"* ]]; then
      pi_model=3
    fi
fi

function restart_moonraker() {
    echo
    echo "INFO: Restarting Moonraker ..."
    sudo systemctl restart moonraker

    timeout=60
    start_time=$(date +%s)

    echo "INFO: Waiting for Moonraker ..."
    while true; do
        KLIPPER_PATH=$(curl localhost:7125/printer/info 2> /dev/null | jq -r .result.klipper_path)
        if [ "$KLIPPER_PATH" = "$BASEDIR/klipper" ]; then
            break;
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            break;
        fi
        sleep 1
    done
}

function update_repo() {
    local repo_dir=$1
    local branch=$2

    if [ -d "${repo_dir}/.git" ]; then
        cd $repo_dir
        branch_ref=$(git rev-parse --abbrev-ref HEAD)
        if [ -n "$branch_ref" ]; then
            git fetch
            if [ $? -ne 0 ]; then
                cd - > /dev/null
                echo "ERROR: Failed to pull latest changes!"
                return 1
            fi

            # clear any local changes
            git reset --hard

            if [ -z "$branch" ]; then
                git reset --hard origin/$branch_ref
            else
                git switch $branch
                if [ $? -eq 0 ]; then
                  git reset --hard origin/$branch
                else
                  echo "ERROR: Failed to switch branches!"
                  return 1
                fi
            fi
            cd - > /dev/null
            sync
        else
            cd - > /dev/null
            echo "ERROR: Failed to detect current branch!"
            return 1
        fi
    else
        echo "ERROR: Invalid $repo_dir specified"
        return 1
    fi
    return 0
}

function update_klipper_mcu() {
  echo
  echo "INFO: Rebuilding Klipper MCU ..."
  cd $BASEDIR/klipper
  cp .config.linux .config
  make clean
  make || exit $?
  rm .config
  sudo systemctl stop klipper-mcu
  sudo cp out/klipper.elf /usr/local/bin/klipper_mcu || exit $?
  sudo systemctl restart klipper-mcu || exit $?
  cd - > /dev/null
}

function update_klipper() {
  echo
  echo "INFO: Stopping Klipper ..."
  sudo systemctl stop klipper

  if [ -d $BASEDIR/cartographer-klipper ] && [ -L $BASEDIR/klipper/klippy/extras/scanner.py ]; then
      $BASEDIR/cartographer-klipper/install.sh || return $?
      sync
  fi

  if [ -d $BASEDIR/beacon-klipper ] && [ -L $BASEDIR/klipper/klippy/extras/beacon.py ]; then
      $BASEDIR/beacon-klipper/install.sh || return $?
      sync
  fi
  $BASEDIR/klippy-env/bin/python3 -m compileall $BASEDIR/klipper/klippy || return $?
  update_klipper_mcu

  echo "INFO: Starting Klipper ..."
  sudo systemctl start klipper
}

function install_config_updater() {
    python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Installing configupdater python package ..."
        command -v pip > /dev/null
        if [ $? -ne 0 ]; then
            echo "INFO: Installing python3-pip ..."
            retry sudo apt-get install -y python3-pip > /dev/null; error
        fi

        # from debian 12 onwards you are expected to create a virtualenv but we can
        # force the config module to be installed in system
        if [ $debian_release -ge 12 ]; then
            sudo pip install --break-system-packages configupdater==3.2 2> /dev/null
        else
            sudo pip install configupdater==3.2
        fi
        python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
        if [ $? -ne 0 ]; then
            echo "ERROR: Something bad happened, can't continue"
            exit 1
        fi
    fi
}

function setup_probe() {
    grep -q "probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up generic probe config ..."

        $CONFIG_HELPER --remove-section "bed_mesh" || exit $?
        $CONFIG_HELPER --remove-section-entry "stepper_z" "position_endstop" || exit $?
        $CONFIG_HELPER --replace-section-entry "stepper_z" "endstop_pin" "probe:z_virtual_endstop" || exit $?

        cp $BASEDIR/pellcorp/config/quickstart.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "quickstart.cfg" || exit $?

        # because we are using force move with 3mm, as a safety feature we will lower the position max
        # by 3mm ootb to avoid damaging the printer if you do a really big print
        position_max=$($CONFIG_HELPER --get-section-entry "stepper_z" "position_max" --minus 3 --integer)
        $CONFIG_HELPER --replace-section-entry "stepper_z" "position_max" "$position_max" || exit $?

        echo "probe" >> $BASEDIR/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function install_cartographer_klipper() {
    local mode=$1

    grep -q "cartographer-klipper" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d $BASEDIR/cartographer-klipper ]; then
            rm -rf $BASEDIR/cartographer-klipper
        fi

        if [ ! -d $BASEDIR/cartographer-klipper ]; then
            echo
            echo "INFO: Installing cartographer-klipper ..."
            git clone https://github.com/cartographer3d/cartographer-klipper.git $BASEDIR/cartographer-klipper || exit $?
        fi
        cd - > /dev/null

        echo
        echo "INFO: Running cartographer-klipper installer ..."
        $BASEDIR/pellcorp/rpi/cartotouch-install.sh || exit $?
        $BASEDIR/klippy-env/bin/python3 -m compileall $BASEDIR/klipper/klippy || exit $?

        echo "cartographer-klipper" >> $BASEDIR/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function install_cartographer_plugin() {
    local mode=$1

    grep -q "cartographer-plugin" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -e $BASEDIR/klipper/klippy/extras/cartographer.py ]; then
            rm -rf $BASEDIR/klipper/klippy/extras/cartographer.py
        fi

        PIP_VERSION=$($BASEDIR/klippy-env/bin/python3 -m pip --version | awk '{print $2}' | tr -d '.')
        if [ $PIP_VERSION -lt 2200 ]; then
          echo
          echo "INFO: Forcing upgrade of PIP ..."
          $BASEDIR/klippy-env/bin/python3 -m pip install --upgrade pip
        fi

        if [ ! -f $BASEDIR/klipper/klippy/extras/cartographer.py ]; then
            curl -s -L https://raw.githubusercontent.com/Cartographer3D/cartographer3d-plugin/refs/heads/main/scripts/install.sh | bash || exit $?
        fi

        echo "cartographer-plugin" >> $BASEDIR/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function install_beacon_klipper() {
    local mode=$1

    grep -q "beacon-klipper" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d $BASEDIR/beacon-klipper ]; then
            rm -rf $BASEDIR/beacon-klipper
        fi

        if [ ! -d $BASEDIR/beacon-klipper ]; then
            echo
            echo "INFO: Installing beacon-klipper ..."
            git clone https://github.com/beacon3d/beacon_klipper $BASEDIR/beacon-klipper || exit $?
        fi

        $BASEDIR/beacon-klipper/install.sh || exit $?
        $BASEDIR/klippy-env/bin/python3 -m compileall $BASEDIR/klipper/klippy || exit $?

        echo "beacon-klipper" >> $BASEDIR/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function cleanup_probe() {
    local probe=$1

    if [ -f $BASEDIR/printer_data/config/${probe}_macro.cfg ]; then
        rm $BASEDIR/printer_data/config/${probe}_macro.cfg
    fi
    $CONFIG_HELPER --remove-include "${probe}_macro.cfg" || exit $?

    if [ "$probe" = "cartotouch" ] || [ "$probe" = "beacon" ]; then
        $CONFIG_HELPER --remove-section-entry "stepper_z" "homing_retract_dist" || exit $?
    fi

    if [ -f $BASEDIR/printer_data/config/$probe.cfg ]; then
        rm $BASEDIR/printer_data/config/$probe.cfg
    fi
    $CONFIG_HELPER --remove-include "$probe.cfg" || exit $?

    # if switching from btt eddy remove this file
    if [ "$probe" = "btteddy" ] && [ -f $BASEDIR/printer_data/config/variables.cfg ]; then
        rm $BASEDIR/printer_data/config/variables.cfg
    fi

    if [ "$probe" = "eddyng" ]; then
        probe=btteddy
    fi

    if [ -f $BASEDIR/printer_data/config/${probe}.conf ]; then
        rm $BASEDIR/printer_data/config/${probe}.conf
    fi

    $CONFIG_HELPER --file moonraker.conf --remove-include "${probe}.conf" || exit $?
}

function cleanup_probes() {
  cleanup_probe microprobe
  cleanup_probe btteddy
  cleanup_probe eddyng
  cleanup_probe cartotouch
  cleanup_probe cartographer
  cleanup_probe beacon
  cleanup_probe klicky
  cleanup_probe bltouch
}

function setup_bltouch() {
    grep -q "bltouch-probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up bltouch/crtouch/3dtouch ..."

        cleanup_probes

        cp $BASEDIR/pellcorp/config/bltouch.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "bltouch.cfg" || exit $?

        cp $BASEDIR/pellcorp/config/bltouch_macro.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "bltouch_macro.cfg" || exit $?

        # for bltouch probe deploy issues occur with safe z at 3
        $CONFIG_HELPER --file homing_override.cfg --replace-section-entry "gcode_macro _SENSORLESS_PARAMS" "variable_safe_z" "5" || exit $?

        # need to add a empty bltouch section for baby stepping to work
        $CONFIG_HELPER --remove-section "bltouch" || exit $?
        $CONFIG_HELPER --add-section "bltouch" || exit $?
        z_offset=$($CONFIG_HELPER --ignore-missing --file $BASEDIR/pellcorp-overrides/printer.cfg.save_config --get-section-entry bltouch z_offset)
        if [ -n "$z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "bltouch" "# z_offset" "0.0" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "bltouch" "z_offset" "0.0" || exit $?
        fi

        if [ -f $BASEDIR/pellcorp-backups/bltouch.factory.cfg ]; then
            $CONFIG_HELPER --file bltouch.cfg --patches $BASEDIR/pellcorp-backups/bltouch.factory.cfg --quiet || exit $?
        fi

        echo "bltouch-probe" >> $BASEDIR/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function setup_microprobe() {
    grep -q "microprobe-probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up microprobe ..."

        cleanup_probes

        cp $BASEDIR/pellcorp/config/microprobe.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "microprobe.cfg" || exit $?

        cp $BASEDIR/pellcorp/config/microprobe_macro.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "microprobe_macro.cfg" || exit $?

        # remove previous directly imported microprobe config
        $CONFIG_HELPER --remove-section "output_pin probe_enable" || exit $?

        # need to add a empty probe section for baby stepping to work
        $CONFIG_HELPER --remove-section "probe" || exit $?
        $CONFIG_HELPER --add-section "probe" || exit $?
        z_offset=$($CONFIG_HELPER --ignore-missing --file $BASEDIR/pellcorp-overrides/printer.cfg.save_config --get-section-entry probe z_offset)
        if [ -n "$z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "probe" "# z_offset" "0.0" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "probe" "z_offset" "0.0" || exit $?
        fi

        if [ -f $BASEDIR/pellcorp-backups/microprobe.factory.cfg ]; then
            $CONFIG_HELPER --file microprobe.cfg --patches $BASEDIR/pellcorp-backups/microprobe.factory.cfg --quiet || exit $?
        fi

        echo "microprobe-probe" >> $BASEDIR/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function setup_klicky() {
    grep -q "klicky-probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up klicky ..."

        cleanup_probes

        cp $BASEDIR/pellcorp/config/klicky.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "klicky.cfg" || exit $?

        # need to add a empty probe section for baby stepping to work
        $CONFIG_HELPER --remove-section "probe" || exit $?
        $CONFIG_HELPER --add-section "probe" || exit $?
        z_offset=$($CONFIG_HELPER --ignore-missing --file $BASEDIR/pellcorp-overrides/printer.cfg.save_config --get-section-entry probe z_offset)
        if [ -n "$z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "probe" "# z_offset" "2.0" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "probe" "z_offset" "2.0" || exit $?
        fi

        cp $BASEDIR/pellcorp/config/klicky_macro.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "klicky_macro.cfg" || exit $?

        if [ -f $BASEDIR/pellcorp-backups/klicky.factory.cfg ]; then
            $CONFIG_HELPER --file klicky.cfg --patches $BASEDIR/pellcorp-backups/klicky.factory.cfg --quiet || exit $?
        fi

        echo "klicky-probe" >> $BASEDIR/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function set_serial_cartotouch() {
    local SERIAL_ID=$(ls /dev/serial/by-id/usb-* | grep "IDM\|Cartographer" | head -1)
    if [ -n "$SERIAL_ID" ]; then
        local EXISTING_SERIAL_ID=$($CONFIG_HELPER --file cartotouch.cfg --get-section-entry "scanner" "serial")
        if [ "$EXISTING_SERIAL_ID" != "$SERIAL_ID" ]; then
            $CONFIG_HELPER --file cartotouch.cfg --replace-section-entry "scanner" "serial" "$SERIAL_ID" || exit $?
            return 1
        else
            echo "Serial value is unchanged"
            return 0
        fi
    else
        echo "WARNING: There does not seem to be a cartographer attached - skipping auto configuration"
        return 0
    fi
}

function set_serial_cartographer() {
    local SERIAL_ID=$(ls /dev/serial/by-id/usb-* | grep "IDM\|Cartographer" | head -1)
    if [ -n "$SERIAL_ID" ]; then
        local EXISTING_SERIAL_ID=$($CONFIG_HELPER --file cartographer.cfg --get-section-entry "mcu cartographer" "serial")
        if [ "$EXISTING_SERIAL_ID" != "$SERIAL_ID" ]; then
            $CONFIG_HELPER --file cartographer.cfg --replace-section-entry "mcu cartographer" "serial" "$SERIAL_ID" || exit $?
            return 1
        else
            echo "Serial value is unchanged"
            return 0
        fi
    else
        echo "WARNING: There does not seem to be a cartographer attached - skipping auto configuration"
        return 0
    fi
}

function setup_cartotouch() {
    grep -q "cartotouch-probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up cartotouch ..."

        cleanup_probes

        # we are adding a new probe so need to migrate file names
        if [ -f $BASEDIR/printer_data/config/cartographer.conf ]; then
          rm $BASEDIR/printer_data/config/cartographer.conf || exit $?
        fi
        $CONFIG_HELPER --file moonraker.conf --remove-include "cartographer.conf" || exit $?

        cp $BASEDIR/pellcorp/rpi/cartotouch.conf $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "cartotouch.conf" || exit $?

        cp $BASEDIR/pellcorp/config/cartotouch_macro.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartotouch_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp $BASEDIR/pellcorp/config/cartotouch.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartotouch.cfg" || exit $?

        # we need to disable the firmware check
        $CONFIG_HELPER --file cartotouch.cfg --replace-section-entry "gcode_macro _CARTOTOUCH_VARIABLES" "variable_verify_firmware" "False" || exit $?

        y_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max" --divisor 2 --integer)
        x_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_max" --divisor 2 --integer)
        $CONFIG_HELPER --file cartotouch.cfg --replace-section-entry "bed_mesh" "zero_reference_position" "$x_position_mid,$y_position_mid" || exit $?

        # for rpi we don't need to turn the camera off
        $CONFIG_HELPER --file cartotouch_macro.cfg --replace-section-entry "gcode_macro BED_MESH_CALIBRATE" "variable_stop_start_camera" "False" || exit $?
        $CONFIG_HELPER --file cartotouch_macro.cfg --replace-section-entry "gcode_macro AXIS_TWIST_COMPENSATION_CALIBRATE" "variable_stop_start_camera" "False" || exit $?

        set_serial_cartotouch

        # as we are referencing the included cartographer now we want to remove the included value
        # from any previous installation
        $CONFIG_HELPER --remove-section "scanner" || exit $?
        $CONFIG_HELPER --add-section "scanner" || exit $?

        scanner_touch_z_offset=$($CONFIG_HELPER --ignore-missing --file $BASEDIR/pellcorp-overrides/printer.cfg.save_config --get-section-entry scanner scanner_touch_z_offset)
        if [ -n "$scanner_touch_z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "scanner" "# scanner_touch_z_offset" "0.05" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "scanner" "scanner_touch_z_offset" "0.05" || exit $?
        fi

        scanner_mode=$($CONFIG_HELPER --ignore-missing --file $BASEDIR/pellcorp-overrides/printer.cfg.save_config --get-section-entry scanner mode)
        if [ -n "$scanner_mode" ]; then
            $CONFIG_HELPER --replace-section-entry "scanner" "# mode" "touch" || exit $?
        else
            $CONFIG_HELPER --replace-section-entry "scanner" "mode" "touch" || exit $?
        fi

        echo "cartotouch-probe" >> $BASEDIR/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function setup_cartographer() {
    grep -q "cartographer-probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up cartographer V2 ..."

        cleanup_probes

        cp $BASEDIR/pellcorp/rpi/cartographer.conf $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "cartographer.conf" || exit $?

        cp $BASEDIR/pellcorp/config/cartographer_macro.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartographer_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp $BASEDIR/pellcorp/config/cartographer.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartographer.cfg" || exit $?

        # we need to disable the firmware check
        $CONFIG_HELPER --file cartographer.cfg --replace-section-entry "gcode_macro _CARTOGRAPHER_VARIABLES" "variable_verify_firmware" "False" || exit $?

        y_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max" --divisor 2 --integer)
        x_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_max" --divisor 2 --integer)
        $CONFIG_HELPER --file cartographer.cfg --replace-section-entry "bed_mesh" "zero_reference_position" "$x_position_mid,$y_position_mid" || exit $?

        # for rpi we don't need to turn the camera off
        $CONFIG_HELPER --file cartographer_macro.cfg --replace-section-entry "gcode_macro BED_MESH_CALIBRATE" "variable_stop_start_camera" "False" || exit $?
        $CONFIG_HELPER --file cartographer_macro.cfg --replace-section-entry "gcode_macro CARTOGRAPHER_AXIS_TWIST_COMPENSATION" "variable_stop_start_camera" "False" || exit $?

        # due to ridiculous issue with cartographer not handling slight out of band temps just set it here and let everyone else use 150
        $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _START_END_PARAMS" "variable_start_preheat_nozzle_temp" 148 || exit $?

        set_serial_cartographer

        echo "cartographer-probe" >> $BASEDIR/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function set_serial_beacon() {
    local SERIAL_ID=$(ls /dev/serial/by-id/usb-Beacon_Beacon* | head -1)
    if [ -n "$SERIAL_ID" ]; then
        local EXISTING_SERIAL_ID=$($CONFIG_HELPER --file beacon.cfg --get-section-entry "beacon" "serial")
        if [ "$EXISTING_SERIAL_ID" != "$SERIAL_ID" ]; then
            $CONFIG_HELPER --file beacon.cfg --replace-section-entry "beacon" "serial" "$SERIAL_ID" || exit $?
            return 1
        else
            echo "Serial value is unchanged"
            return 0
        fi
    else
        echo "WARNING: There does not seem to be a beacon attached - skipping auto configuration"
        return 0
    fi
}

function setup_beacon() {
    grep -q "beacon-probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up beacon ..."

        cleanup_probes

        cp $BASEDIR/pellcorp/rpi/beacon.conf $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "beacon.conf" || exit $?

        cp $BASEDIR/pellcorp/config/beacon_macro.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "beacon_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp $BASEDIR/pellcorp/config/beacon.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "beacon.cfg" || exit $?

        # for beacon can't use homing override
        $CONFIG_HELPER --file homing_override.cfg --remove-section "homing_override"

        y_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max" --divisor 2 --integer)
        x_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_max" --divisor 2 --integer)
        $CONFIG_HELPER --file beacon.cfg --replace-section-entry "beacon" "home_xy_position" "$x_position_mid,$y_position_mid" || exit $?
        $CONFIG_HELPER --file beacon.cfg --replace-section-entry "bed_mesh" "zero_reference_position" "$x_position_mid,$y_position_mid" || exit $?

        # for rpi we don't need to turn the camera off
        $CONFIG_HELPER --file beacon_macro.cfg --replace-section-entry "gcode_macro BED_MESH_CALIBRATE" "variable_stop_start_camera" "False" || exit $?
        $CONFIG_HELPER --file beacon_macro.cfg --replace-section-entry "gcode_macro AXIS_TWIST_COMPENSATION_CALIBRATE" "variable_stop_start_camera" "False" || exit $?

        set_serial_beacon

        $CONFIG_HELPER --remove-section "beacon" || exit $?
        $CONFIG_HELPER --add-section "beacon" || exit $?

        beacon_cal_nozzle_z=$($CONFIG_HELPER --ignore-missing --file $BASEDIR/pellcorp-overrides/printer.cfg.save_config --get-section-entry beacon cal_nozzle_z)
        if [ -n "$beacon_cal_nozzle_z" ]; then
          $CONFIG_HELPER --replace-section-entry "beacon" "# cal_nozzle_z" "0.1" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "beacon" "cal_nozzle_z" "0.1" || exit $?
        fi

        echo "beacon-probe" >> $BASEDIR/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function set_serial_btteddy() {
    local SERIAL_ID=$(ls /dev/serial/by-id/usb-Klipper_rp2040* | head -1)
    if [ -n "$SERIAL_ID" ]; then
        local EXISTING_SERIAL_ID=$($CONFIG_HELPER --file btteddy.cfg --get-section-entry "mcu eddy" "serial")
        if [ "$EXISTING_SERIAL_ID" != "$SERIAL_ID" ]; then
            $CONFIG_HELPER --file btteddy.cfg --replace-section-entry "mcu eddy" "serial" "$SERIAL_ID" || exit $?
            return 1
        else
            echo "Serial value is unchanged"
            return 0
        fi
    else
        echo "WARNING: There does not seem to be a btt eddy attached - skipping auto configuration"
        return 0
    fi
}

function setup_btteddy() {
    grep -q "btteddy-probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up btteddy ..."

        cleanup_probes

        cp $BASEDIR/pellcorp/config/btteddy.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy.cfg" || exit $?

        set_serial_btteddy

        cp $BASEDIR/pellcorp/config/btteddy_macro.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy_macro.cfg" || exit $?

        $CONFIG_HELPER --remove-section "probe_eddy_current btt_eddy" || exit $?
        $CONFIG_HELPER --add-section "probe_eddy_current btt_eddy" || exit $?

        # for rpi we don't need to turn the camera off
        $CONFIG_HELPER --file btteddy_macro.cfg --replace-section-entry "gcode_macro BTTEDDY_CURRENT_CALIBRATE" "variable_stop_start_camera" "False" || exit $?
        $CONFIG_HELPER --file btteddy_macro.cfg --replace-section-entry "gcode_macro BTTEDDY_TEMPERATURE_PROBE_CALIBRATE" "variable_stop_start_camera" "False" || exit $?

        echo "btteddy-probe" >> $BASEDIR/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function set_serial_eddyng() {
    local SERIAL_ID=$(ls /dev/serial/by-id/usb-Klipper_rp2040* | head -1)
    if [ -n "$SERIAL_ID" ]; then
        local EXISTING_SERIAL_ID=$($CONFIG_HELPER --file eddyng.cfg --get-section-entry "mcu eddy" "serial")
        if [ "$EXISTING_SERIAL_ID" != "$SERIAL_ID" ]; then
            $CONFIG_HELPER --file eddyng.cfg --replace-section-entry "mcu eddy" "serial" "$SERIAL_ID" || exit $?
            return 1
        else
            echo "Serial value is unchanged"
            return 0
        fi
    else
        echo "WARNING: There does not seem to be a btt eddy ng attached - skipping auto configuration"
        return 0
    fi
}

function setup_eddyng() {
    grep -q "eddyng-probe" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up btt eddy-ng ..."

        cleanup_probes

        cp $BASEDIR/pellcorp/config/eddyng.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "eddyng.cfg" || exit $?

        set_serial_eddyng

        cp $BASEDIR/pellcorp/config/eddyng_macro.cfg $BASEDIR/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "eddyng_macro.cfg" || exit $?

        $CONFIG_HELPER --remove-section "probe_eddy_ng btt_eddy" || exit $?
        $CONFIG_HELPER --add-section "probe_eddy_ng btt_eddy" || exit $?

        # for rpi we don't need to turn the camera off
        $CONFIG_HELPER --file eddyng_macro.cfg --replace-section-entry "gcode_macro BED_MESH_CALIBRATE" "variable_stop_start_camera" "False" || exit $?

        echo "eddyng-probe" >> $BASEDIR/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function apply_overrides() {
    return_status=0
    grep -q "overrides" $BASEDIR/pellcorp.done
    if [ $? -ne 0 ]; then
        $BASEDIR/pellcorp/tools/apply-overrides.sh
        return_status=$?
        echo "overrides" >> $BASEDIR/pellcorp.done
        sync
    fi
    return $return_status
}

# the start_end.cfg CLIENT_VARIABLE configuration must be based on the printer.cfg max positions after
# mount overrides and user overrides have been applied
function fixup_client_variables_config() {
    echo
    echo "INFO: Fixing up client variables ..."

    changed=0
    kinematics=$($CONFIG_HELPER --get-section-entry "printer" "kinematics")
    if [ "$kinematics" = "corexy" ] || [ "$kinematics" = "cartesian" ]; then
      # position_min is optional so we need a fallback
      position_min_x=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_min" --integer --default-value 0)
      position_min_y=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_min" --integer --default-value 0)
      position_max_x=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_max" --integer)
      position_max_y=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max" --integer)
      variable_custom_park_y=$($CONFIG_HELPER --file start_end.cfg --get-section-entry "gcode_macro _CLIENT_VARIABLE" "variable_custom_park_y" --integer)
      variable_custom_park_x=$($CONFIG_HELPER --file start_end.cfg --get-section-entry "gcode_macro _CLIENT_VARIABLE" "variable_custom_park_x" --integer)
      variable_park_at_cancel_y=$($CONFIG_HELPER --file start_end.cfg --get-section-entry "gcode_macro _CLIENT_VARIABLE" "variable_park_at_cancel_y" --integer)
      variable_park_at_cancel_x=$($CONFIG_HELPER --file start_end.cfg --get-section-entry "gcode_macro _CLIENT_VARIABLE" "variable_park_at_cancel_x" --integer)

      if [ $position_max_x -le $position_min_x ]; then
          echo "ERROR: The stepper_x position_max seems to be incorrect: $position_max_x"
          return 0
      fi
      if [ $position_max_y -le $position_min_y ]; then
          echo "ERROR: The stepper_y position_max seems to be incorrect: $position_max_y"
          return 0
      fi

      if [ -z "$variable_custom_park_y" ]; then
          echo "ERROR: The variable_custom_park_y has no value"
          return 0
      fi
      if [ -z "$variable_custom_park_x" ]; then
          echo "ERROR: The variable_custom_park_x has no value"
          return 0
      fi
      if [ -z "$variable_park_at_cancel_y" ]; then
          echo "ERROR: The variable_park_at_cancel_y has no value"
          return 0
      fi
      if [ -z "$variable_park_at_cancel_x" ]; then
          echo "ERROR: The variable_park_at_cancel_x has no value"
          return 0
      fi

      if [ $variable_custom_park_x -eq 0 ] || [ $variable_custom_park_x -ge $position_max_x ] || [ $variable_custom_park_x -le $position_min_x ]; then
          pause_park_x=$((position_max_x - 10))
          if [ $pause_park_x -ne $variable_custom_park_x ]; then
            echo "Overriding variable_custom_park_x to $pause_park_x (was $variable_custom_park_x)"
            $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _CLIENT_VARIABLE" "variable_custom_park_x" $pause_park_x
            changed=1
          fi
      fi

      if [ $variable_custom_park_y -eq 0 ] || [ $variable_custom_park_y -le $position_min_y ]; then
            pause_park_y=$(($position_min_y + 10))
            if [ $pause_park_y -ne $variable_custom_park_y ]; then
                echo "Overriding variable_custom_park_y to $pause_park_y (was $variable_custom_park_y)"
                $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _CLIENT_VARIABLE" "variable_custom_park_y" $pause_park_y
                changed=1
            fi
      fi

      # as long as parking has not been overriden
      if [ $variable_park_at_cancel_x -eq 0 ] || [ $variable_park_at_cancel_x -ge $position_max_x ]; then
          custom_park_x=$((position_max_x - 10))
          if [ $custom_park_x -ne $variable_park_at_cancel_x ]; then
              echo "Overriding variable_park_at_cancel_x to $custom_park_x (was $variable_park_at_cancel_x)"
              $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _CLIENT_VARIABLE" "variable_park_at_cancel_x" $custom_park_x
              changed=1
          fi
      fi

      if [ $variable_park_at_cancel_y -eq 0 ] || [ $variable_park_at_cancel_y -ge $position_max_y ]; then
            custom_park_y=$((position_max_y - 10))
            if [ $custom_park_y -ne $variable_park_at_cancel_y ]; then
                echo "Overriding variable_park_at_cancel_y to $custom_park_y (was $variable_park_at_cancel_y)"
                $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _CLIENT_VARIABLE" "variable_park_at_cancel_y" $custom_park_y
                changed=1
            fi
      fi
    fi
    sync
    return $changed
}

mkdir -p $BASEDIR/printer_data/config/images
mkdir -p $BASEDIR/printer_data/logs
mkdir -p $BASEDIR/printer_data/gcodes

# special mode to update the repo only
# this stuff we do not want to have a log file for
if [ "$1" = "--update-branch" ]; then
    update_repo $BASEDIR/pellcorp
    exit $?
elif [ "$1" = "--cleanup" ]; then # mostly to make testing easier
    echo "INFO: Running cleanup ..."
    [ -f $BASEDIR/pellcorp.done ] && rm $BASEDIR/pellcorp.done
    [ -d $BASEDIR/pellcorp-backups ] && rm -rf $BASEDIR/pellcorp-backups
    [ -d $BASEDIR/pellcorp-overrides ] && rm -rf $BASEDIR/pellcorp-overrides
    [ -d $BASEDIR/printer_data ] && rm -rf $BASEDIR/printer_data
    [ -d $BASEDIR/klipper ] && rm -rf $BASEDIR/klipper
    [ -d $BASEDIR/klippy-env ] && rm -rf $BASEDIR/klippy-env
    [ -f /usr/local/bin/klipper_mcu ] && sudo rm /usr/local/bin/klipper_mcu
    [ -d $BASEDIR/moonraker ] && rm -rf $BASEDIR/moonraker
    [ -d $BASEDIR/moonraker-env ] && rm -rf $BASEDIR/moonraker-env
    [ -d $BASEDIR/moonraker-timelapse ] && rm -rf $BASEDIR/moonraker-timelapse
    [ -d $BASEDIR/fluidd ] && rm -rf $BASEDIR/fluidd
    [ -d $BASEDIR/mainsail ] && rm -rf $BASEDIR/mainsail
    [ -d $BASEDIR/crowsnest ] && rm -rf $BASEDIR/crowsnest
    [ -d $BASEDIR/fluidd-config ] && rm -rf $BASEDIR/fluidd-config
    [ -d $BASEDIR/guppyscreen ] && rm -rf $BASEDIR/guppyscreen
    [ -d $BASEDIR/KlipperScreen ] && rm -rf $BASEDIR/KlipperScreen
    [ -d $BASEDIR/cartographer-klipper ] && rm -rf $BASEDIR/cartographer-klipper
    [ -d $BASEDIR/beacon-klipper ] && rm -rf $BASEDIR/beacon-klipper
    exit 0
elif [ "$1" = "--branch" ] && [ -n "$2" ]; then # convenience for testing new features
    update_repo $BASEDIR/pellcorp $2 || exit $?
    exit $?
elif [ "$1" = "--klipper-branch" ]; then # convenience for testing new features
    if [ -n "$2" ]; then
        update_repo $BASEDIR/klipper $2 || exit $?
        update_klipper || exit $?
        exit 0
    else
        echo "Error invalid branch specified"
        exit 1
    fi
fi

export TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE=$BASEDIR/printer_data/logs/installer-$TIMESTAMP.log

cd $BASEDIR/pellcorp
PELLCORP_GIT_SHA=$(git rev-parse HEAD)
cd - > /dev/null

PELLCORP_UPDATED_SHA=
if [ -f $BASEDIR/pellcorp.done ]; then
  PELLCORP_UPDATED_SHA=$(cat $BASEDIR/pellcorp.done | grep "installed_sha" | awk -F '=' '{print $2}')
fi

mkdir -p $BASEDIR/pellcorp-backups
mkdir -p $BASEDIR/pellcorp-overrides

if [ $# -gt 0 ] && [ "$1" != "--fix-serial" ]; then
  # diet-pi dont have this file
  if [ -f /var/cache/apt/pkgcache.bin ]; then
    # https://unix.stackexchange.com/a/271058
    now=$(date +%s)
    last_update=$(stat -c %Y /var/cache/apt/pkgcache.bin)
    # if not updated for a day refresh
    if [ $((now - last_update)) -gt 86400 ]; then
      retry sudo apt-get --error-on=any update; error
    fi
  fi
  install_config_updater
fi

{
  # figure out what existing probe if any is being used
  probe=
  if [ -f $BASEDIR/printer_data/config/bltouch.cfg ]; then
    probe=bltouch
  elif [ -f $BASEDIR/printer_data/config/microprobe.cfg ]; then
    probe=microprobe
  elif [ -f $BASEDIR/printer_data/config/cartotouch.cfg ]; then
    probe=cartotouch
  elif [ -f $BASEDIR/printer_data/config/cartographer.cfg ]; then
      probe=cartographer
  elif [ -f $BASEDIR/printer_data/config/beacon.cfg ]; then
    probe=beacon
  elif [ -f $BASEDIR/printer_data/config/klicky.cfg ]; then
    probe=klicky
  elif [ -f $BASEDIR/printer_data/config/eddyng.cfg ]; then
    probe=eddyng
  elif [ -f $BASEDIR/printer_data/config/btteddy.cfg ]; then
    probe=btteddy
  elif [ -f $BASEDIR/pellcorp.done ]; then # only if an existing install do we treat is as probe=none
    probe=none
  fi

  mode=install
  force=false
  skip_overrides=false
  probe_switch=false
  printer=
  mount=
  existing_printer=$(cat $BASEDIR/pellcorp-overrides/config.info 2> /dev/null | grep printer= | awk -F '=' '{print $2}')

  if [ -f $BASEDIR/pellcorp.done ]; then
    install_mount=$(cat $BASEDIR/pellcorp.done | grep "mount=" | awk -F '=' '{print $2}')
  fi

  while true; do
    if [ "$1" = "--fix-client-variables" ] || [ "$1" = "--fix-serial" ] || [ "$1" = "--install" ] || [ "$1" = "--update" ] || [ "$1" = "--reinstall" ] || [ "$1" = "--clean-install" ] || [ "$1" = "--clean-update" ] || [ "$1" = "--clean-reinstall" ]; then
      mode=$(echo $1 | sed 's/--//g')
      shift
      if [ "$mode" = "clean-install" ] || [ "$mode" = "clean-reinstall" ] || [ "$mode" = "clean-update" ]; then
        skip_overrides=true
        mode=$(echo $mode | sed 's/clean-//g')
      fi
    elif [ "$1" = "--mount" ]; then
      shift
      mount=$1

      if [ -z "$mount" ]; then
        mount=unknown
      fi
      shift
    elif [ "$1" = "--printer" ]; then
      shift
      printer=$1
      if [ -z "$printer" ]; then
        printer=unknown
      fi
      shift

      if [ "$mode" = "reinstall" ] || [ ! -f $BASEDIR/pellcorp.done ]; then
        $BASEDIR/pellcorp/rpi/tools/apply-printer-cfg.sh --verify $printer
        if [ $? -eq 0 ]; then
          echo "INFO: Printer is $printer"
        else
          exit 1
        fi
      fi
    elif [ "$1" = "--force" ]; then
      force=true
      shift
    elif [ "$1" = "--probe" ]; then # allow the installer to specify a `--probe` argument for clarity
      shift
    elif [ "$1" = "none" ] || [ "$1" = "microprobe" ] || [ "$1" = "bltouch" ] || [ "$1" = "beacon" ] || [ "$1" = "klicky" ] || [ "$1" = "cartographer" ] || [ "$1" = "cartotouch" ] || [ "$1" = "btteddy" ] || [ "$1" = "eddyng" ]; then
      if [ "$mode" = "fix-serial" ]; then
        echo "ERROR: Switching probes is not supported while trying to fix serial!"
        exit 1
      fi
      if [ "$mode" = "update" ] && [ -n "$probe" ] && [ "$1" != "$probe" ]; then
        echo "WARNING: About to switch from $probe to $1!"
        probe_switch=true
      fi
      probe=$1
      shift
    elif [ -n "$1" ]; then # no more valid parameters
      break
    else # no more parameters
      break
    fi
  done

  if [ "$mode" = "fix-serial" ]; then
    if [ -f $BASEDIR/pellcorp.done ]; then
      if [ "$probe" = "cartotouch" ]; then
        set_serial_cartotouch
        set_serial=$?
      elif [ "$probe" = "cartographer" ]; then
        set_serial_cartographer
        set_serial=$?
      elif [ "$probe" = "beacon" ]; then
        set_serial_beacon
        set_serial=$?
      elif [ "$probe" = "btteddy" ]; then
        set_serial_btteddy
        set_serial=$?
      elif [ "$probe" = "eddyng" ]; then
        set_serial_eddyng
        set_serial=$?
      else
        echo "ERROR: Fix serial not supported for $probe"
        exit 1
      fi
    else
      echo "ERROR: No installation found"
      exit 1
    fi
    if [ $set_serial -ne 0 ]; then
      echo "INFO: Restarting Klipper ..."
      sudo systemctl restart klipper
    fi
    exit 0
  elif [ "$mode" = "fix-client-variables" ]; then
    if [ -f $BASEDIR/pellcorp.done ]; then
      fixup_client_variables_config
      fixup_client_variables_config=$?
      if [ $fixup_client_variables_config -ne 0 ]; then
        if [ "$client" = "cli" ]; then
          echo
          echo "INFO: Restarting Klipper ..."
          sudo systemctl restart klipper
        else
          echo "WARNING: Klipper restart required"
        fi
      else
        echo "INFO: No changes made"
      fi
      exit 0
    else
      echo "ERROR: No installation found"
      exit 1
    fi
  fi

  # if using a standard base printer can continue to use it no need to respecify it
  if [ -z "$printer" ] && [ "$mode" != "update" ]; then
    if [ "$mode" = "reinstall" ] && [ -n "$existing_printer" ] && [ -f $BASEDIR/pellcorp/rpi/printers/${existing_printer}.cfg ]; then
      printer=${existing_printer}
      echo "INFO: Printer is $printer"
    else
      echo "ERROR: Printer --printer argument is required"
      exit 1
    fi
  fi

  if [ -z "$probe" ]; then
    echo "ERROR: You must specify a probe you want to configure"
    echo "One of: [microprobe, bltouch, cartotouch, cartographer, btteddy, eddyng, beacon, klicky]"
    exit 1
  fi

  mkdir -p $BASEDIR/backups
  ln -sf $BASEDIR/backups $BASEDIR/printer_data/config/

  mkdir -p $BASEDIR/pellcorp-overrides
  mkdir -p $BASEDIR/pellcorp-backups

  echo "INFO: Mode is $mode"
  echo "INFO: Probe is $probe"

  if [ -n "$PELLCORP_UPDATED_SHA" ]; then
    if [ "$mode" = "install" ]; then
      echo
      echo "ERROR: Installation has already completed - NO CHANGES WERE MADE!"
      echo
      if [ "$PELLCORP_UPDATED_SHA" != "$PELLCORP_GIT_SHA" ]; then
        echo "Perhaps you meant to execute an --update or a --reinstall instead!"
        echo "  https://pellcorp.github.io/creality-wiki/updating/#updating"
        echo "  https://pellcorp.github.io/creality-wiki/updating/#reinstalling"
      fi
      echo
      exit 1
    elif [ "$mode" = "update" ] && [ "$PELLCORP_UPDATED_SHA" = "$PELLCORP_GIT_SHA" ] && [ "$probe_switch" != "true" ] && [ "$force" != "true" ] && [ -z "$mount" ]; then
      echo
      echo "ERROR: Installation is already up to date - NO CHANGES WERE MADE!"
      echo
      echo "Perhaps you forgot to execute a --branch main first!"
      echo "  https://pellcorp.github.io/creality-wiki/updating/#updating"
      echo
      exit 1
    fi
  fi

  # do not backup unless there are actually files in the config directory
  if [ $(find $BASEDIR/printer_data/config -type f | wc -l) -gt 0 ]; then
    echo "INFO: Backing up existing configuration ..."
    TIMESTAMP=${TIMESTAMP} $BASEDIR/pellcorp/tools/backups.sh --create
  fi

  # this sets up the base printer definition
  if [ -n "$printer" ] && [ "$mode" != "update" ]; then
    $BASEDIR/pellcorp/rpi/tools/apply-printer-cfg.sh $printer || exit $?
  fi

  model=$(cat $BASEDIR/pellcorp-backups/printer.factory.cfg | grep MODEL: | awk -F ':' '{print $2}')
  # if a printer.cfg is specified without a MODEL we skip mount overrides
  if [ -z "$model" ]; then
    model=unspecified
  fi

  # we skip mount overrides for a special unspecified model
  if [ "$model" != "unspecified" ]; then
    if [ -f $BASEDIR/pellcorp.done ]; then
      install_mount=$(cat $BASEDIR/pellcorp.done | grep "mount=" | awk -F '=' '{print $2}')
    fi

    # don't try and validate a mount if all we are wanting to do is fix serial
    if [ -z "$mount" ] && [ -n "$install_mount" ] && [ "$probe_switch" != "true" ]; then
      # for a partial install where we selected a mount, we can grab it from the pellcorp.done file
      if [ "$mode" = "install" ]; then
        mount=$install_mount
      fi
    elif [ -n "$mount" ] && [ -n "$install_mount" ]; then
      if [ "$mount" = "%CURRENT%" ]; then
        mount=$install_mount
      fi

      if [ "$mount" = "$install_mount" ] && [ "$probe_switch" != "true" ] && [ "$force" != "true" ]; then
        echo "ERROR: You have specified --mount $mount for your existing mount!"
        echo "INFO: If you know what you are doing you can force reapplying mount overrides with --force"
        exit 1
      fi
    fi

    if [ -n "$mount" ]; then
      $BASEDIR/pellcorp/tools/apply-mount-overrides.sh --verify $probe $mount $model
      if [ $? -eq 0 ]; then
        echo "INFO: Mount is $mount"
      else
        exit 1
      fi
    elif [ "$skip_overrides" = "true" ] || [ "$mode" = "install" ] || [ "$mode" = "reinstall" ]; then
      echo "ERROR: Mount option must be specified"
      exit 1
    elif [ -f $BASEDIR/pellcorp.done ]; then
      if [ -z "$install_mount" ] || [ "$probe_switch" = "true" ]; then
        echo "ERROR: Mount option must be specified"
        exit 1
      else
        echo "INFO: Mount is $install_mount"
      fi
    fi
    echo
  fi

  if [ "$skip_overrides" = "true" ]; then
    echo "INFO: Configuration overrides will not be saved or applied"
  fi

  if [ -f $BASEDIR/printer_data/config/printer.cfg ]; then # this is an update or a reinstall
    # before going ahead with the update lets stop a bunch of things to just make it easier
    if [ "$(sudo systemctl is-enabled moonraker 2> /dev/null)" = "enabled" ]; then
      echo "INFO: Stopping Moonraker ..."
      sudo systemctl stop moonraker
    fi

    if [ "$(sudo systemctl is-enabled klipper 2> /dev/null)" = "enabled" ]; then
      echo "INFO: Stopping Klipper ..."
      sudo systemctl stop klipper
    fi

    if [ "$(sudo systemctl is-enabled grumpyscreen 2> /dev/null)" = "enabled" ]; then
      echo "INFO: Stopping GrumpyScreen ..."
      sudo systemctl stop grumpyscreen
    fi

    if [ "$(sudo systemctl is-enabled KlipperScreen 2> /dev/null)" = "enabled" ]; then
      echo "INFO: Stopping KlipperScreen ..."
      sudo systemctl stop KlipperScreen
    fi

    if [ -f $BASEDIR/pellcorp.done ]; then
      if [ "$skip_overrides" != "true" ]; then
        $BASEDIR/pellcorp/tools/config-overrides.sh
      fi

      rm $BASEDIR/pellcorp.done
    fi
  fi

  if [ "$mode" = "reinstall" ]; then
    # where the base printer was changed we need to clear out any overrides as they are unsafe to try and reapply
    # also we only reapply if the base printer is built in, because we have NO idea if an existing adhoc (either file or url)
    # is sufficiently alike for it to be safe to reapply config overrides
    if [ -z "$existing_printer" ] || [ "$printer" != "$existing_printer" ] || [ ! -f $BASEDIR/pellcorp/rpi/printers/${printer}.cfg ]; then
      [ -f $BASEDIR/pellcorp-overrides/printer.cfg ] && rm $BASEDIR/pellcorp-overrides/printer.cfg
    fi
    [ -d $BASEDIR/printer_data/config/ ] && rm -rf $BASEDIR/printer_data
  fi

  mkdir -p $BASEDIR/printer_data/config/
  cp $BASEDIR/pellcorp-backups/printer.factory.cfg $BASEDIR/printer_data/config/printer.cfg

  if [ "$model" != "unspecified" ] && [ ! -f $BASEDIR/pellcorp.done ]; then
    # we need a flag to know what mount we are using
    if [ -n "$mount" ]; then
      echo "mount=$mount" > $BASEDIR/pellcorp.done
    elif [ -n "$install_mount" ]; then
      echo "mount=$install_mount" > $BASEDIR/pellcorp.done
    fi
  fi

  # lets make sure we are not stranded in some repo dir
  cd ~

  touch $BASEDIR/pellcorp.done

  $BASEDIR/pellcorp/rpi/install-moonraker.sh $mode
  if [ $? -ne 0 ]; then
    echo "FATAL: Moonraker installation failed - aborting"
    exit 1
  fi

  if [ "$(sudo systemctl is-enabled crowsnest 2> /dev/null)" = "disabled" ]; then
    echo "INFO: Crowsnest is disabled"
  else
    $BASEDIR/pellcorp/rpi/install-crowsnest.sh $mode
  fi

  $BASEDIR/pellcorp/rpi/install-fluidd.sh $mode || exit $?
  if [ $? -ne 0 ]; then
    echo "FATAL: Fluidd installation failed - aborting"
    exit 1
  fi

  $BASEDIR/pellcorp/rpi/install-mainsail.sh $mode || exit $?
  if [ $? -ne 0 ]; then
    echo "FATAL: Mainsail installation failed - aborting"
    exit 1
  fi

  $BASEDIR/pellcorp/rpi/install-nginx.sh $mode || exit $?
  if [ $? -ne 0 ]; then
    echo "FATAL: NGinx installation failed - aborting"
    exit 1
  fi

  $BASEDIR/pellcorp/rpi/install-klipper.sh $mode $probe || exit $?
  if [ $? -ne 0 ]; then
    echo "FATAL: Klipper installation failed - aborting"
    exit 1
  fi

  install_cartographer_klipper=0
  install_cartographer_plugin=0
  install_beacon_klipper=0
  if [ "$probe" = "cartotouch" ]; then
    install_cartographer_klipper $mode
    install_cartographer_klipper=$?
  elif [ "$probe" = "cartographer" ]; then
    install_cartographer_plugin $mode
    install_cartographer_plugin=$?
  elif [ "$probe" = "beacon" ]; then
    install_beacon_klipper $mode
    install_beacon_klipper=$?
  fi

  echo
  if [ "$(sudo systemctl is-enabled grumpyscreen 2> /dev/null)" = "disabled" ]; then
    echo "INFO: GrumpyScreen is disabled"
  elif [ "$(sudo systemctl is-enabled KlipperScreen 2> /dev/null)" = "disabled" ]; then
    echo "INFO: KlipperScreen is disabled"
  fi
  if [ "$(sudo systemctl is-enabled grumpyscreen 2> /dev/null)" = "enabled" ]; then
    echo
    $BASEDIR/pellcorp/rpi/install-grumpyscreen.sh $mode || exit $?
  elif [ "$(sudo systemctl is-enabled KlipperScreen 2> /dev/null)" = "enabled" ]; then
     echo "INFO: Skipping KlipperScreen $mode"
  else
    echo "INFO: Skipping Grumpyscreen and KlipperScreen installation"
  fi

  setup_probe=0
  setup_probe_specific=0
  if [ "$probe" != "none" ]; then
    setup_probe
    setup_probe=$?
    if [ "$probe" = "cartotouch" ]; then
      setup_cartotouch
      setup_probe_specific=$?
    elif [ "$probe" = "cartographer" ]; then
      setup_cartographer
      setup_probe_specific=$?
    elif [ "$probe" = "bltouch" ]; then
      setup_bltouch
      setup_probe_specific=$?
    elif [ "$probe" = "btteddy" ]; then
      setup_btteddy
      setup_probe_specific=$?
    elif [ "$probe" = "eddyng" ]; then
      setup_eddyng
      setup_probe_specific=$?
    elif [ "$probe" = "microprobe" ]; then
      setup_microprobe
      setup_probe_specific=$?
    elif [ "$probe" = "beacon" ]; then
      setup_beacon
      setup_probe_specific=$?
    elif [ "$probe" = "klicky" ]; then
      setup_klicky
      setup_probe_specific=$?
    else
      echo "ERROR: Probe $probe not supported"
      exit 1
    fi
  else
    # for delta this file is missing
    $CONFIG_HELPER --ignore-missing --file start_end.cfg --replace-section-entry "gcode_macro _START_END_PARAMS" "variable_activate_bed_mesh" "False"
  fi

  # we want a copy of the file before config overrides are re-applied so we can correctly generate diffs
  # against different generations of the original file
  for file in printer.cfg start_end.cfg fan_control.cfg ${probe}.conf spoolman.conf timelapse.conf moonraker.conf crowsnest.conf webcam.conf useful_macros.cfg homing_override.cfg ${probe}_macro.cfg ${probe}.cfg; do
    if [ -f $BASEDIR/printer_data/config/$file ]; then
      cp $BASEDIR/printer_data/config/$file $BASEDIR/pellcorp-backups/$file
    fi
  done

  if [ "$skip_overrides" != "true" ]; then
    apply_overrides
  fi

  if [ "$model" != "unspecified" ] && [ -n "$mount" ]; then
    $BASEDIR/pellcorp/tools/apply-mount-overrides.sh $probe $mount $model
  fi

  fixup_client_variables_config
  fixup_client_variables_config=$?
  if [ $fixup_client_variables_config -eq 0 ]; then
    echo "INFO: No changes made"
  fi

  echo "INFO: Restarting Moonraker ..."
  sudo systemctl restart moonraker

  echo "INFO: Restarting Klipper ..."
  sudo systemctl restart klipper

  if [ "$(sudo systemctl is-enabled grumpyscreen 2> /dev/null)" = "enabled" ]; then
    echo "INFO: Restarting GrumpyScreen ..."
    sudo systemctl restart grumpyscreen
  fi

  if [ "$(sudo systemctl is-enabled KlipperScreen 2> /dev/null)" = "enabled" ]; then
    echo "INFO: Restarting KlipperScreen ..."
    sudo systemctl restart KlipperScreen
  fi

  echo "installed_sha=$PELLCORP_GIT_SHA" >> $BASEDIR/pellcorp.done
  sync

  exit 0
} 2>&1 | tee -a $LOG_FILE
