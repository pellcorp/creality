#!/bin/sh

# this allows us to make changes to Simple AF and grumpyscreen in parallel
GRUMPYSCREEN_TIMESTAMP=1751793600

MODEL=$(/usr/bin/get_sn_mac.sh model)
if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ] || [ "$MODEL" = "K1 SE" ]; then
  model=k1
elif [ "$MODEL" = "CR-K1 Max" ] || [ "$MODEL" = "K1 Max SE" ]; then
  model=k1m
elif [ "$MODEL" = "F004" ]; then
  model=f004
elif [ "$MODEL" = "F005" ]; then
  model=f005
else
  echo "FATAL: This script is not supported for $MODEL!"
  exit 1
fi

# we only need to verify we are not trying to install on really old k1 firmware
if [ "$MODEL" != "F004" ] && [ "$MODEL" != "F005" ]; then
    # 6. prefix is the prefix I use for pre-rooted firmware
    ota_version=$(cat /etc/ota_info | grep ota_version | awk -F '=' '{print $2}' | sed 's/^6.//g' | tr -d '.')
    if [ -z "$ota_version" ] || [ $ota_version -lt 1335 ]; then
      echo "FATAL: Firmware is too old, you must update to at least version 1.3.3.5 of Creality OS"
      echo "https://www.creality.com/pages/download-k1-flagship"
      exit 1
    fi
fi

if [ -d /usr/data/helper-script ] || [ -f /usr/data/fluidd.sh ] || [ -f /usr/data/mainsail.sh ]; then
    if [ -f /usr/data/pellcorp.done ]; then
        echo "FATAL: You have broken your Simple AF install by corrupting it with Helper Script!"
    else
        echo "FATAL: You must factory reset the printer before installing Simple AF!"
    fi
    exit 1
fi

# everything else in the script assumes its cloned to /usr/data/pellcorp
# so we must verify this or shit goes wrong
if [ "$(dirname $(readlink -f $0))" != "/usr/data/pellcorp/k1" ]; then
  >&2 echo "FATAL: This git repo must be cloned to /usr/data/pellcorp"
  exit 1
fi

# so we can do ~/pellcorp/ paths in the wiki
ln -sf /usr/data/pellcorp/ /root

# kill pip cache to free up overlayfs
rm -rf /root/.cache
sync

REMAINING_ROOT_DISK=$(df -m / | tail -1 | awk '{print $4}')
if [ $REMAINING_ROOT_DISK -gt 25 ]; then
    echo "INFO: There is $(df -h / | tail -1 | awk '{print $4}') remaining on your / partition"
else
    echo "CRITICAL: Remaining / space is critically low!"
    echo "CRITICAL: There is $(df -h / | tail -1 | awk '{print $4}') remaining on your / partition"
    exit 1
fi

REMAINING_TMP_DISK=$(df -m /tmp | tail -1 | awk '{print $4}')
if [ $REMAINING_TMP_DISK -gt 25 ]; then
    echo "INFO: There is $(df -h /tmp | tail -1 | awk '{print $4}') remaining on your /tmp partition"
else
    echo "CRITICAL: Remaining /tmp space is critically low!"
    echo "CRITICAL: There is $(df -h /tmp | tail -1 | awk '{print $4}') remaining on your /tmp partition"
    exit 1
fi

REMAINING_DATA_DISK=$(df -m /usr/data | tail -1 | awk '{print $4}')
if [ $REMAINING_DATA_DISK -gt 1000 ]; then
    echo "INFO: There is $(df -h /usr/data | tail -1 | awk '{print $4}') remaining on your /usr/data partition"
else
    echo "CRITICAL: Remaining disk space is critically low!"
    echo "CRITICAL: There is $(df -h /usr/data | tail -1 | awk '{print $4}') remaining on your /usr/data partition"
    exit 1
fi
echo

cp /usr/data/pellcorp/k1/services/S45cleanup /etc/init.d || exit $?
cp /usr/data/pellcorp/k1/services/S58factoryreset /etc/init.d || exit $?
cp /usr/data/pellcorp/k1/services/S50dropbear /etc/init.d/ || exit $?
sync

# for k1 the installed curl does not do ssl, so we replace it first
# and we can then make use of it going forward
cp /usr/data/pellcorp/k1/tools/curl /usr/bin/curl || exit $?
sync

CONFIG_HELPER="/usr/data/pellcorp/tools/config-helper.py"

# thanks to @Nestaa51 for the timeout changes to not wait forever for moonraker
function restart_moonraker() {
    echo
    echo "INFO: Restarting Moonraker ..."
    sudo systemctl restart moonraker

    timeout=60
    start_time=$(date +%s)

    # this is mostly for k1-qemu where Moonraker takes a while to start up
    echo "INFO: Waiting for Moonraker ..."
    while true; do
        KLIPPER_PATH=$(curl localhost:7125/printer/info 2> /dev/null | jq -r .result.klipper_path)
        # moonraker will start reporting the location of klipper as /usr/data/klipper when using a soft link
        if [ "$KLIPPER_PATH" = "/usr/share/klipper" ] || [ "$KLIPPER_PATH" = "/usr/data/klipper" ]; then
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

function update_klipper() {
  if [ -d /usr/data/cartographer-klipper ]; then
      /usr/data/cartographer-klipper/install.sh || return $?
      ln -sf /usr/data/cartographer-klipper/ /root
      sync
  fi
  if [ -d /usr/data/beacon-klipper ]; then
      /usr/data/pellcorp/k1/beacon-install.sh || return $?
      ln -sf /usr/data/beacon-klipper/ /root
      sync
  fi
  /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || return $?
  /usr/data/pellcorp/k1/tools/check-firmware.sh --status
  if [ $? -eq 0 ]; then
      echo "INFO: Restarting Klipper ..."
      sudo systemctl restart klipper
  fi
  return $?
}

function install_config_updater() {
    python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Installing configupdater python package ..."
        pip3 install configupdater==3.2

        python3 -c 'from configupdater import ConfigUpdater' 2> /dev/null
        if [ $? -ne 0 ]; then
            echo "ERROR: Something bad happened, can't continue"
            exit 1
        fi
    fi

    # old pellcorp-env not required anymore
    if [ -d /usr/data/pellcorp-env/ ]; then
        rm -rf /usr/data/pellcorp-env/
    fi
    sync
}

function disable_creality_services() {
    if [ ! -L /etc/boot-display/part0 ]; then
      # clean up failed installation of custom boot display
      rm -rf /overlay/upper/etc/boot-display/*
      rm -rf /overlay/upper/etc/logo/*
      rm -f /overlay/upper/etc/init.d/S12boot_display
      rm -f /overlay/upper/etc/init.d/S11jpeg_display_shell
      mount -o remount /
    fi

    if [ -f /etc/init.d/S99start_app ]; then
        echo
        echo "INFO: Disabling some creality services ..."

        echo "INFO: If you reboot the printer before installing grumpyscreen, the screen will be blank - this is to be expected!"
        /etc/init.d/S99start_app stop > /dev/null 2>&1
        rm /etc/init.d/S99start_app

        if [ -f /etc/init.d/S70cx_ai_middleware ]; then
            /etc/init.d/S70cx_ai_middleware stop > /dev/null 2>&1
            rm /etc/init.d/S70cx_ai_middleware
        fi
        if [ -f /etc/init.d/S97webrtc ]; then
            /etc/init.d/S97webrtc stop > /dev/null 2>&1
            rm /etc/init.d/S97webrtc
        fi
        if [ -f /etc/init.d/S99mdns ]; then
            /etc/init.d/S99mdns stop > /dev/null 2>&1
            rm /etc/init.d/S99mdns
        fi
        if [ -f /etc/init.d/S96wipe_data ]; then
            wipe_data_pid=$(ps -ef | grep wipe_data | grep -v "grep" | awk '{print $1}')
            if [ -n "$wipe_data_pid" ]; then
                kill -9 $wipe_data_pid
            fi
            rm /etc/init.d/S96wipe_data
        fi
        if [ -f /etc/init.d/S55klipper_service ]; then
            /etc/init.d/S55klipper_service stop > /dev/null 2>&1
        fi

        if [ -f /etc/init.d/S57klipper_mcu ]; then
            /etc/init.d/S57klipper_mcu stop > /dev/null 2>&1
            if [ "$MODEL" != "F005" ]; then
              rm /etc/init.d/S57klipper_mcu
            fi
        fi

        # the log main process takes up so much memory a lot of it swapped, killing this process might make the
        # installer go a little more quickly as there is no swapping going on
        log_main_pid=$(ps -ef | grep log_main | grep -v "grep" | awk '{print $1}')
        if [ -n "$log_main_pid" ]; then
            kill -9 $log_main_pid
        fi

        # remove the old gcode files provided by creality as they should not be printed
        if [ -d /usr/data/printer_data/gcodes/ ]; then
            rm /usr/data/printer_data/gcodes/*.gcode 2> /dev/null
        fi

        # move rubbish to delete
        if [ -d /usr/data/creality/userdata/log ]; then
          rm -rf /usr/data/creality/userdata/log
        fi

        if [ -d /usr/data/creality/upgrade ]; then
          rm -rf /usr/data/creality/upgrade
        fi

        echo "Fixing up default printer config ..."
        cat /usr/data/printer_data/config/printer.cfg | grep '^#\*#' > /usr/data/printer.cfg.save_config

        # clean out the calibration data from the end of the printer.cfg file
        sed -i '/#\*#.*/d' /usr/data/printer_data/config/printer.cfg

        extruder_pid=$($CONFIG_HELPER --file /usr/data/printer.cfg.save_config --get-section-entry "extruder" "control")
        # we have save config overrides for extruder so we have to restore the defaults so that
        if [ -n "$extruder_pid" ]; then
            extruder_pid_kp=$($CONFIG_HELPER --file /usr/data/printer.cfg.save_config --get-section-entry "extruder" "pid_kp" --default-value "0")
            extruder_pid_ki=$($CONFIG_HELPER --file /usr/data/printer.cfg.save_config --get-section-entry "extruder" "pid_ki" --default-value "0")
            extruder_pid_kd=$($CONFIG_HELPER --file /usr/data/printer.cfg.save_config --get-section-entry "extruder" "pid_kd" --default-value "0")
            $CONFIG_HELPER --replace-section-entry "extruder" "control" "pid"
            $CONFIG_HELPER --replace-section-entry "extruder" "pid_kp" "$extruder_pid_kp"
            $CONFIG_HELPER --replace-section-entry "extruder" "pid_ki" "$extruder_pid_ki"
            $CONFIG_HELPER --replace-section-entry "extruder" "pid_kd" "$extruder_pid_kd"
        fi

        heater_pid=$($CONFIG_HELPER --file /usr/data/printer.cfg.save_config --get-section-entry "heater_bed" "control")
        if [ -n "$heater_pid" ]; then
          heater_pid_kp=$($CONFIG_HELPER --file /usr/data/printer.cfg.save_config --get-section-entry "heater_bed" "pid_kp" --default-value "0")
          heater_pid_ki=$($CONFIG_HELPER --file /usr/data/printer.cfg.save_config --get-section-entry "extruder" "pid_ki" --default-value "0")
          heater_pid_kd=$($CONFIG_HELPER --file /usr/data/printer.cfg.save_config --get-section-entry "extruder" "pid_kd" --default-value "0")
          $CONFIG_HELPER --replace-section-entry "heater_bed" "control" "pid"
          $CONFIG_HELPER --replace-section-entry "heater_bed" "pid_kp" "$heater_pid_kp"
          $CONFIG_HELPER --replace-section-entry "heater_bed" "pid_ki" "$heater_pid_ki"
          $CONFIG_HELPER --replace-section-entry "heater_bed" "pid_kd" "$heater_pid_kd"
        fi

        # clean up the extra commented out crap
        sed -i '/^#\s*control:/d' /usr/data/printer_data/config/printer.cfg
        sed -i '/^#\s*pid_[Kk]p:/d' /usr/data/printer_data/config/printer.cfg
        sed -i '/^#\s*pid_[Kk]i:/d' /usr/data/printer_data/config/printer.cfg
        sed -i '/^#\s*pid_[Kk]d:/d' /usr/data/printer_data/config/printer.cfg

        rm /usr/data/printer.cfg.save_config
    fi

    # this is mostly backwards compatible
    if [ -f /etc/init.d/S57klipper_mcu ]; then
        /etc/init.d/S55klipper_service stop > /dev/null 2>&1
        /etc/init.d/S57klipper_mcu stop > /dev/null 2>&1
        if [ "$MODEL" != "F005" ]; then
          rm /etc/init.d/S57klipper_mcu
        fi
    fi
    sync
}

function install_boot_display() {
  grep -q "boot-display" /usr/data/pellcorp.done
  if [ $? -ne 0 ]; then
    echo
    echo "INFO: Installing custom boot display ..."

    # shamelessly stolen from https://github.com/Guilouz/Creality-Helper-Script/blob/main/scripts/custom_boot_display.sh
    rm -rf /etc/boot-display/part0
    cp /usr/data/pellcorp/k1/boot-display.conf /etc/boot-display/
    cp /usr/data/pellcorp/k1/services/S11jpeg_display_shell /etc/init.d/
    mkdir -p /usr/data/boot-display
    tar -zxf "/usr/data/pellcorp/k1/boot-display.tar.gz" -C /usr/data/boot-display
    ln -s /usr/data/boot-display/part0 /etc/boot-display/
    echo "boot-display" >> /usr/data/pellcorp.done
    sync
    return 1
  fi
  return 0
}

function install_webcam() {
    local mode=$1

    grep -q "webcam" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] || [ ! -f /opt/bin/mjpg_streamer ]; then
            echo
            echo "INFO: Installing mjpg streamer ..."
            /opt/bin/opkg install mjpg-streamer mjpg-streamer-input-http mjpg-streamer-input-uvc mjpg-streamer-output-http mjpg-streamer-www || exit $?
        fi

        echo "INFO: Updating webcam config ..."
        # we do not want to start the entware version of the service ever
        if [ -f /opt/etc/init.d/S96mjpg-streamer ]; then
            rm /opt/etc/init.d/S96mjpg-streamer
        fi
        # kill the existing creality services so that we can use the app right away without a restart
        pidof cam_app &>/dev/null && killall -TERM cam_app > /dev/null 2>&1
        pidof mjpg_streamer &>/dev/null && killall -TERM mjpg_streamer > /dev/null 2>&1

        if [ -f /etc/init.d/S50webcam ]; then
            /etc/init.d/S50webcam stop > /dev/null 2>&1
        fi

        # auto_uvc.sh is responsible for starting the web cam_app
        [ -f /usr/bin/auto_uvc.sh ] && rm /usr/bin/auto_uvc.sh
        cp /usr/data/pellcorp/k1/files/auto_uvc.sh /usr/bin/
        chmod 777 /usr/bin/auto_uvc.sh

        cp /usr/data/pellcorp/k1/services/S50webcam /etc/init.d/
        /etc/init.d/S50webcam start

        if [ -f /usr/data/pellcorp.ipaddress ]; then
          # don't wipe the pellcorp.ipaddress if its been explicitly set to skip
          PREVIOUS_IP_ADDRESS=$(cat /usr/data/pellcorp.ipaddress 2> /dev/null)
          if [ "$PREVIOUS_IP_ADDRESS" != "skip" ]; then
            rm /usr/data/pellcorp.ipaddress
          fi
        fi
        cp /usr/data/pellcorp/k1/webcam.conf /usr/data/printer_data/config/ || exit $?

        echo "webcam" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function install_moonraker() {
    local mode=$1

    grep -q "moonraker" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo

        if [ "$mode" != "update" ] && [ -d /usr/data/moonraker ]; then
            if [ -f /etc/init.d/S56moonraker_service ]; then
                /etc/init.d/S56moonraker_service stop
            fi
            if [ -d /usr/data/printer_data/database/ ]; then
                [ -f /usr/data/moonraker-database.tar.gz ] && rm /usr/data/moonraker-database.tar.gz

                echo "INFO: Backing up moonraker database ..."
                cd /usr/data/printer_data/

                tar -zcf /usr/data/moonraker-database.tar.gz database/
                cd
            fi
            rm -rf /usr/data/moonraker
        fi

        if [ "$mode" != "update" ] && [ -d /usr/data/moonraker-env ]; then
            rm -rf /usr/data/moonraker-env
        elif [ ! -d /usr/data/moonraker-env/lib/python3.8/site-packages/dbus_fast ] || [ -d /usr/data/moonraker-env/lib/python3.8/site-packages/apprise-1.7.1.dist-info ]; then
            rm -rf /usr/data/moonraker-env
        fi

        if [ -d /usr/data/moonraker/.git ]; then
            cd /usr/data/moonraker
            MOONRAKER_URL=$(git remote get-url origin)
            cd - > /dev/null
            if [ "$MOONRAKER_URL" != "https://github.com/pellcorp/moonraker.git" ]; then
                echo "INFO: Forcing moonraker to switch to pellcorp/moonraker"
                rm -rf /usr/data/moonraker
            fi
        fi

        if [ ! -d /usr/data/moonraker/.git ]; then
            echo "INFO: Installing moonraker ..."

            [ -d /usr/data/moonraker ] && rm -rf /usr/data/moonraker
            [ -d /usr/data/moonraker-env ] && rm -rf /usr/data/moonraker-env

            echo
            if [ "$AF_GIT_CLONE" = "ssh" ]; then
                export GIT_SSH_IDENTITY=moonraker
                export GIT_SSH=/usr/data/pellcorp/k1/ssh/git-ssh.sh
                git clone git@github.com:pellcorp/moonraker.git /usr/data/moonraker || exit $?
                cd /usr/data/moonraker && git remote set-url origin https://github.com/pellcorp/moonraker.git && cd - > /dev/null
            else
                git clone https://github.com/pellcorp/moonraker.git /usr/data/moonraker || exit $?
            fi

            if [ -f /usr/data/moonraker-database.tar.gz ]; then
                echo
                echo "INFO: Restoring moonraker database ..."
                cd /usr/data/printer_data/
                tar -zxf /usr/data/moonraker-database.tar.gz
                rm /usr/data/moonraker-database.tar.gz
                cd
            fi
        fi

        if [ ! -f /usr/data/moonraker-timelapse/component/timelapse.py ]; then
            if [ -d /usr/data/moonraker-timelapse ]; then
                rm -rf /usr/data/moonraker-timelapse
            fi
            git clone https://github.com/mainsail-crew/moonraker-timelapse.git /usr/data/moonraker-timelapse/ || exit $?
        fi

        if [ ! -d /usr/data/moonraker-env ]; then
            tar -zxf /usr/data/pellcorp/k1/moonraker-env.tar.gz -C /usr/data/ || exit $?
        fi

        if [ "$mode" != "update" ] || [ ! -f /opt/bin/ffmpeg ]; then
            echo "INFO: Upgrading ffmpeg for moonraker timelapse ..."
            /opt/bin/opkg install ffmpeg || exit $?
        fi

        echo "INFO: Updating moonraker config ..."

        # an existing bug where the moonraker secrets was not correctly copied
        if [ ! -f /usr/data/printer_data/moonraker.secrets ]; then
            cp /usr/data/pellcorp/config/moonraker.secrets /usr/data/printer_data/
        fi

        ln -sf /usr/data/pellcorp/k1/tools/supervisorctl /usr/bin/ || exit $?
        ln -sf /usr/data/pellcorp/k1/tools/systemctl /usr/bin/ || exit $?
        ln -sf /usr/data/pellcorp/k1/tools/sudo /usr/bin/ || exit $?
        cp /usr/data/pellcorp/k1/services/S56moonraker_service /etc/init.d/ || exit $?
        cp /usr/data/pellcorp/k1/moonraker.conf /usr/data/printer_data/config/ || exit $?
        ln -sf /usr/data/pellcorp/k1/moonraker.asvc /usr/data/printer_data/ || exit $?

        ln -sf /usr/data/moonraker-timelapse/component/timelapse.py /usr/data/moonraker/moonraker/components/ || exit $?
        if ! grep -q "moonraker/components/timelapse.py" "/usr/data/moonraker/.git/info/exclude"; then
            echo "moonraker/components/timelapse.py" >> "/usr/data/moonraker/.git/info/exclude"
        fi
        ln -sf /usr/data/moonraker-timelapse/klipper_macro/timelapse.cfg /usr/data/printer_data/config/ || exit $?
        cp /usr/data/pellcorp/k1/timelapse.conf /usr/data/printer_data/config/ || exit $?

        ln -sf /usr/data/pellcorp/config/spoolman.cfg /usr/data/printer_data/config/ || exit $?
        cp /usr/data/pellcorp/config/spoolman.conf /usr/data/printer_data/config/ || exit $?

        # after an initial install do not overwrite notifier.conf or moonraker.secrets
        if [ ! -f /usr/data/printer_data/config/notifier.conf ]; then
            cp /usr/data/pellcorp/config/notifier.conf /usr/data/printer_data/config/ || exit $?
        fi
        if [ ! -f /usr/data/printer_data/moonraker.secrets ]; then
            cp /usr/data/pellcorp/config/moonraker.secrets /usr/data/printer_data/ || exit $?
        fi

        echo "moonraker" >> /usr/data/pellcorp.done
        sync

        # means nginx and moonraker need to be restarted
        return 1
    fi
    return 0
}

function install_nginx() {
    local mode=$1

    grep -q "nginx" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        default_ui=fluidd
        if [ -f /usr/data/nginx/nginx/sites/mainsail ]; then
          grep "#listen" /usr/data/nginx/nginx/sites/mainsail > /dev/null
          if [ $? -ne 0 ]; then
            default_ui=mainsail
          fi
        fi

        if [ "$mode" != "update" ] && [ -d /usr/data/nginx ]; then
            if [ -f /etc/init.d/S50nginx_service ]; then
                /etc/init.d/S50nginx_service stop
            fi
            rm -rf /usr/data/nginx
        fi

        if [ ! -d /usr/data/nginx ]; then
            echo
            echo "INFO: Installing nginx ..."

            tar -zxf /usr/data/pellcorp/k1/nginx.tar.gz -C /usr/data/ || exit $?
        fi

        echo "INFO: Updating nginx config ..."
        cp /usr/data/pellcorp/k1/nginx.conf /usr/data/nginx/nginx/ || exit $?
        mkdir -p /usr/data/nginx/nginx/sites/
        cp /usr/data/pellcorp/k1/nginx/fluidd /usr/data/nginx/nginx/sites/ || exit $?
        cp /usr/data/pellcorp/k1/nginx/mainsail /usr/data/nginx/nginx/sites/ || exit $?

        if [ "$default_ui" = "mainsail" ]; then
          echo "INFO: Restoring mainsail as default UI"
          sed -i 's/.*listen 80 default_server;/    #listen 80 default_server;/g' /usr/data/nginx/nginx/sites/fluidd || exit $?
          sed -i 's/.*#listen 80 default_server;/    listen 80 default_server;/g' /usr/data/nginx/nginx/sites/mainsail || exit $?
        fi

        cp /usr/data/pellcorp/k1/services/S50nginx_service /etc/init.d/ || exit $?

        echo "nginx" >> /usr/data/pellcorp.done
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

function install_fluidd() {
    local mode=$1

    grep -q "fluidd" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/fluidd ]; then
            rm -rf /usr/data/fluidd
        fi

        if [ ! -d /usr/data/fluidd ]; then
            echo
            echo "INFO: Installing fluidd ..."

            mkdir -p /usr/data/fluidd || exit $?
            curl -L "https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip" -o /usr/data/fluidd.zip || exit $?
            unzip -qd /usr/data/fluidd /usr/data/fluidd.zip || exit $?
            rm /usr/data/fluidd.zip
        fi

        echo "fluidd" >> /usr/data/pellcorp.done
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

function install_mainsail() {
    local mode=$1

    grep -q "mainsail" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/mainsail ]; then
            rm -rf /usr/data/mainsail
        fi

        if [ ! -d /usr/data/mainsail ]; then
            echo
            echo "INFO: Installing mainsail ..."

            mkdir -p /usr/data/mainsail || exit $?
            curl -L "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o /usr/data/mainsail.zip || exit $?
            unzip -qd /usr/data/mainsail /usr/data/mainsail.zip || exit $?
            rm /usr/data/mainsail.zip
        fi

        # the mainsail and fluidd client.cfg are exactly the same
        [ -f /usr/data/printer_data/config/mainsail.cfg ] && rm /usr/data/printer_data/config/mainsail.cfg

        echo "mainsail" >> /usr/data/pellcorp.done
        sync

        # means nginx needs to be restarted
        return 1
    fi
    return 0
}

function install_klipper() {
    local mode=$1
    local probe=$2

    grep -q "klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo

        if [ -d /usr/data/klipper/.git ]; then
            cd /usr/data/klipper/
            remote_repo=$(git remote get-url origin | awk -F '/' '{print $NF}' | sed 's/.git//g')
            cd - > /dev/null
            if [ "$remote_repo" != "klipper" ] && [ "$remote_repo" != "crapper" ]; then
                echo "INFO: Forcing Klipper repo to be switched from pellcorp/${remote_repo} to pellcorp/klipper"
                rm -rf /usr/data/klipper/
            fi
        fi

        if [ ! -d /usr/data/klipper/.git ]; then
            echo "INFO: Installing klipper ..."

            if [ "$AF_GIT_CLONE" = "ssh" ]; then
                export GIT_SSH_IDENTITY=klipper
                export GIT_SSH=/usr/data/pellcorp/k1/ssh/git-ssh.sh
                git clone git@github.com:pellcorp/klipper.git /usr/data/klipper || exit $?
                # reset the origin url to make moonraker happy
                cd /usr/data/klipper && git remote set-url origin https://github.com/pellcorp/klipper.git && cd - > /dev/null
            else
                git clone https://github.com/pellcorp/klipper.git /usr/data/klipper || exit $?
            fi
            [ -d /usr/share/klipper ] && rm -rf /usr/share/klipper
        else
            cd /usr/data/klipper/
            branch_ref=$(git rev-parse --abbrev-ref HEAD)
            remote_repo=$(git remote get-url origin | awk -F '/' '{print $NF}' | sed 's/.git//g')
            git log | grep -q "add SET_KINEMATIC_POSITION CLEAR=Z feature to allow us to clear z in sensorless.cfg"
            klipper_status=$?
            cd - > /dev/null

            # force update
            if [ ! -f /usr/data/klipper/fw/K1/klipper_host_mcu ]; then
              klipper_status=1
            fi

            # force klipper update to get reverted kinematic position feature
            if [ "$remote_repo" = "klipper" ] && [ $klipper_status -ne 0 ] && [ "$branch_ref" = "master" ]; then
                echo "INFO: Forcing update of klipper to latest master"
                update_repo /usr/data/klipper master || exit $?
            fi
        fi

        # get rid of kamp
        if [ -e /usr/data/printer_data/config/KAMP ]; then
          rm /usr/data/printer_data/config/KAMP
        fi

        if [ -f /usr/data/printer_data/config/KAMP_Settings.cfg ]; then
          rm /usr/data/printer_data/config/KAMP_Settings.cfg
        fi

        if [ -d /usr/data/KAMP ]; then
          rm -rf /usr/data/KAMP
        fi

        echo "INFO: Updating klipper config ..."
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        ln -sf /usr/data/klipper /usr/share/ || exit $?

        ln -sf /usr/data/klipper/fw/K1/klipper_host_mcu /usr/bin/klipper_mcu

        # for scripts like ~/klipper/scripts, a soft link makes things a little bit easier
        ln -sf /usr/data/klipper/ /root

        # add a USB link to the gcodes directory so that grumpyscreen can print from USB
        if [ ! -L /usr/data/printer_data/gcodes/usb ]; then
          ln -sf /tmp/udisk/sda1 /usr/data/printer_data/gcodes/usb
        fi
        
        cp /usr/data/pellcorp/k1/services/S55klipper_service /etc/init.d/ || exit $?

        # currently no support for updating firmware on Ender 5 Max or Ender 3 V3 KE!
        if [ "$MODEL" != "F004" ] && [ "$MODEL" != "F005" ]; then
            cp /usr/data/pellcorp/k1/services/S13mcu_update /etc/init.d/ || exit $?
        fi

        cp /usr/data/pellcorp/config/sensorless.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "sensorless.cfg" || exit $?

        # just make sure the baud is written
        $CONFIG_HELPER --replace-section-entry "mcu" "baud" 230400 || exit $?

        $CONFIG_HELPER --replace-section-entry "mcu nozzle_mcu" "baud" 230400 || exit $?

        kinematics=$($CONFIG_HELPER --get-section-entry "printer" "kinematics")

        # for Ender 5 Max we need to disable sensorless homing, reversing homing order,don't move away and do not repeat homing
        # but we are still going to use homing override even though the max has physical endstops to make things a bit easier
        if [ "$MODEL" = "F004" ]; then
            $CONFIG_HELPER --file sensorless.cfg --replace-section-entry "gcode_macro _SENSORLESS_PARAMS" "variable_home_y_before_x" "True" || exit $?
        fi

        if [ "$kinematics" = "corexy" ]; then # by default we want to home twice when using sensorless
            $CONFIG_HELPER --file sensorless.cfg --replace-section-entry "gcode_macro _SENSORLESS_PARAMS" "variable_repeat_home_xy" "True" || exit $?
        fi

        cp /usr/data/pellcorp/k1/internal_macros.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "internal_macros.cfg" || exit $?

        cp /usr/data/pellcorp/config/useful_macros.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "useful_macros.cfg" || exit $?

        if [ "$MODEL" != "F005" ]; then
          # the klipper_mcu is not even used, so just get rid of it
          $CONFIG_HELPER --remove-section "mcu rpi" || exit $?
        fi

        cp /usr/data/pellcorp/k1/belts_calibration.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "belts_calibration.cfg" || exit $?

        # ender 5 max does not support ADXL in the toolhead and bed because of klipper
        # version incompatibility, for Ender 3 V3 KE we are hoping to use the nebula
        # ADXL adaptors and that requires klipper mcu, so if the klipper mcu is
        # still enabled leave the adxl config intact
        remove_adxl=false
        if [ "$MODEL" = "F004" ]; then
          remove_adxl=true
        elif [ "$MODEL" = "F005" ] && [ ! -f /etc/init.d/S57klipper_mcu ]; then
          remove_adxl=true
        fi
        if [ "$remove_adxl" = "true" ]; then
          # for ender 5 max we can't use on board adxl and only beacon and cartotouch support
          # for Ender 3 V3 KE we have more work to do to support the nebula pad adxl in the future
          if [ "$probe" != "beacon" ] && [ "$probe" != "cartotouch" ]; then
              $CONFIG_HELPER --remove-section "adxl345" || exit $?
              $CONFIG_HELPER --remove-section "resonance_tester" || exit $?
          fi
        fi

        # F004 and F005 already have the /usr/bin/beep command
        if [ "$MODEL" != "F004" ] && [ "$MODEL" != "F005" ]; then
          cp /usr/data/pellcorp/k1/files/beep /usr/bin/
        fi

        $CONFIG_HELPER --remove-section "Height_module2" || exit $?
        $CONFIG_HELPER --remove-section "output_pin aobi" || exit $?
        $CONFIG_HELPER --remove-section "output_pin USB_EN" || exit $?
        $CONFIG_HELPER --remove-section "hx711s" || exit $?
        $CONFIG_HELPER --remove-section "filter" || exit $?
        $CONFIG_HELPER --remove-section "dirzctl" || exit $?
        $CONFIG_HELPER --remove-section "accel_chip_proxy" || exit $?
        $CONFIG_HELPER --remove-section "z_compensate" || exit $?
        $CONFIG_HELPER --remove-section "mcu leveling_mcu" || exit $?
        $CONFIG_HELPER --remove-section "bl24c16f" || exit $?
        $CONFIG_HELPER --remove-section "prtouch_v2" || exit $?
        $CONFIG_HELPER --remove-section "output_pin power" || exit $?
        $CONFIG_HELPER --remove-section-entry "printer" "square_corner_max_velocity" || exit $?
        $CONFIG_HELPER --remove-section-entry "printer" "max_accel_to_decel" || exit $?
        $CONFIG_HELPER --remove-section-entry "stepper_y" "gcode_position_max" || exit $?
        $CONFIG_HELPER --remove-section "filament_switch_sensor filament_sensor_2" || exit $?
        
        # https://www.klipper3d.org/TMC_Drivers.html#prefer-to-not-specify-a-hold_current
        $CONFIG_HELPER --remove-section-entry "tmc2209 stepper_x" "hold_current" || exit $?
        $CONFIG_HELPER --remove-section-entry "tmc2209 stepper_y" "hold_current" || exit $?

        $CONFIG_HELPER --remove-include "printer_params.cfg" || exit $?
        $CONFIG_HELPER --remove-include "gcode_macro.cfg" || exit $?
        $CONFIG_HELPER --remove-include "custom_gcode.cfg" || exit $?
        $CONFIG_HELPER --remove-include "box.cfg" || exit $?

        if [ -f /usr/data/printer_data/config/custom_gcode.cfg ]; then
            rm /usr/data/printer_data/config/custom_gcode.cfg
        fi

        if [ -f /usr/data/printer_data/config/gcode_macro.cfg ]; then
            rm /usr/data/printer_data/config/gcode_macro.cfg
        fi

        if [ -f /usr/data/printer_data/config/printer_params.cfg ]; then
            rm /usr/data/printer_data/config/printer_params.cfg
        fi

        if [ -f /usr/data/printer_data/config/factory_printer.cfg ]; then
            rm /usr/data/printer_data/config/factory_printer.cfg
        fi

        cp /usr/data/pellcorp/config/start_end.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "start_end.cfg" || exit $?

        if [ "$probe" != "beacon" ] && [ "$probe" != "cartotouch" ] && [ "$probe" != "eddyng" ]; then
            $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _START_END_PARAMS" "variable_start_print_bed_heating_move_bed_distance" "0" || exit $?
        fi

        if [ "$kinematics" = "cartesian" ] || [ "$MODEL" = "K1 SE" ]; then
          # for cartesian no cool down necessary
          $CONFIG_HELPER --file start_end.cfg --replace-section-entry "gcode_macro _START_END_PARAMS" "variable_end_print_cool_down" "False" || exit $?
        fi

        ln -sf /usr/data/pellcorp/config/Line_Purge.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "Line_Purge.cfg" || exit $?

        ln -sf /usr/data/pellcorp/config/Smart_Park.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "Smart_Park.cfg" || exit $?

        if [ -f /usr/data/pellcorp/k1/fan_control.${model}.cfg ]; then
            cp /usr/data/pellcorp/k1/fan_control.${model}.cfg /usr/data/printer_data/config/fan_control.cfg || exit $?
        else
            cp /usr/data/pellcorp/k1/fan_control.cfg /usr/data/printer_data/config || exit $?
        fi
        $CONFIG_HELPER --add-include "fan_control.cfg" || exit $?

        # K1 SE has no chamber fan
        if [ "$MODEL" = "K1 SE" ]; then
            $CONFIG_HELPER --file fan_control.cfg --remove-section "gcode_macro M191" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --remove-section "gcode_macro M141" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --remove-section "temperature_sensor chamber_temp" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --remove-section "temperature_fan chamber_fan" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --remove-section "fan_generic chamber" || exit $?
            $CONFIG_HELPER --file fan_control.cfg --replace-section-entry "duplicate_pin_override" "pins" "PC5" || exit $?
        elif [ "$MODEL" = "F004" ]; then
            $CONFIG_HELPER --remove-section "output_pin MainBoardFan" || exit $?
            $CONFIG_HELPER --remove-section "output_pin en_nozzle_fan" || exit $?
            $CONFIG_HELPER --remove-section "output_pin en_fan0" || exit $?
            $CONFIG_HELPER --remove-section "output_pin en_fan1" || exit $?
            $CONFIG_HELPER --remove-section "output_pin col_pwm" || exit $?
            $CONFIG_HELPER --remove-section "output_pin col" || exit $?
            $CONFIG_HELPER --remove-section "heater_fan nozzle_fan" || exit $?
        elif [ "$MODEL" = "F005" ]; then
          $CONFIG_HELPER --remove-section "output_pin MainBoardFan" || exit $?
          $CONFIG_HELPER --remove-section "heater_fan nozzle_fan" || exit $?
          $CONFIG_HELPER --remove-section "bltouch" || exit $?
          $CONFIG_HELPER --remove-section-entry "heater_bed" "temp_offset_flag" || exit $?
        fi

        $CONFIG_HELPER --remove-section "output_pin fan0" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan1" || exit $?
        $CONFIG_HELPER --remove-section "output_pin fan2" || exit $?

        # a few strange duplicate pins appear in some firmware
        $CONFIG_HELPER --remove-section "output_pin PA0" || exit $?
        $CONFIG_HELPER --remove-section "output_pin PB2" || exit $?
        $CONFIG_HELPER --remove-section "output_pin PB10" || exit $?
        $CONFIG_HELPER --remove-section "output_pin PC8" || exit $?
        $CONFIG_HELPER --remove-section "output_pin PC9" || exit $?

        # duplicate pin can only be assigned once, so we remove it from printer.cfg so we can
        # configure it in fan_control.cfg
        $CONFIG_HELPER --remove-section "duplicate_pin_override" || exit $?

        # no longer required as we configure the part fan entirely in fan_control.cfg
        $CONFIG_HELPER --remove-section "static_digital_output my_fan_output_pins" || exit $?

        # moving the heater_fan to fan_control.cfg
        $CONFIG_HELPER --remove-section "heater_fan hotend_fan" || exit $?

        # all the fans and temp sensors are going to fan control now
        $CONFIG_HELPER --remove-section "temperature_sensor mcu_temp" || exit $?
        $CONFIG_HELPER --remove-section "temperature_sensor chamber_temp" || exit $?
        $CONFIG_HELPER --remove-section "temperature_fan chamber_fan" || exit $?

        # just in case anyone manually has added this to printer.cfg
        $CONFIG_HELPER --remove-section "temperature_fan mcu_fan" || exit $?

        # the nozzle should not trigger the MCU anymore
        $CONFIG_HELPER --remove-section "multi_pin heater_fans" || exit $?

        # moving idle timeout to start_end.cfg so we can have some integration with
        # start and end print and warp stabilisation if needed
        $CONFIG_HELPER --remove-section "idle_timeout" || exit $?

        # just in case its missing from stock printer.cfg make sure it gets added
        $CONFIG_HELPER --add-section "exclude_object" || exit $?

        if [ "$mode" != "update" ] && [ -d /usr/data/fluidd-config ]; then
            rm -rf /usr/data/fluidd-config
        fi

        if [ ! -d /usr/data/fluidd-config ]; then
            echo
            echo "INFO: Updating client macros ..."

            git clone https://github.com/fluidd-core/fluidd-config.git /usr/data/fluidd-config || exit $?
        fi

        [ -e /usr/data/printer_data/config/fluidd.cfg ] && rm /usr/data/printer_data/config/fluidd.cfg

        ln -sf /usr/data/fluidd-config/client.cfg /usr/data/printer_data/config/
        $CONFIG_HELPER --add-include "client.cfg" || exit $?

        # for moonraker to be able to use moonraker fluidd/mainsail client.cfg out of the box need to
        # have $HOME/printer_data resolve correctly.
        ln -sf /usr/data/printer_data/ /root

        # these are already defined in fluidd config so get rid of them from printer.cfg
        $CONFIG_HELPER --remove-section "pause_resume" || exit $?
        $CONFIG_HELPER --remove-section "display_status" || exit $?
        $CONFIG_HELPER --remove-section "virtual_sdcard" || exit $?

        if $CONFIG_HELPER --section-exists "filament_switch_sensor filament_sensor"; then
          $CONFIG_HELPER --replace-section-entry "filament_switch_sensor filament_sensor" "runout_gcode" "_ON_FILAMENT_RUNOUT" || exit $?
          # the _ON_FILAMENT_RUNOUT macro is going to be in control of filament runout now and avoid triggering another
          # runout event if already paused
          $CONFIG_HELPER --replace-section-entry "filament_switch_sensor filament_sensor" "pause_on_runout" "false" || exit $?
        else
          echo
          echo "WARN: No filament sensor configured skipping on filament runout configuration"
        fi

        echo "klipper" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function install_guppyscreen() {
    local mode=$1
    local branch=$2

    grep -q "guppyscreen" /usr/data/pellcorp.done
    if [ $? -ne 0 ] || [ "$mode" = "switch-branch" ]; then
        echo

        if [ "$mode" != "update" ] && [ -d /usr/data/guppyscreen ]; then
            if [ -f /etc/init.d/S99guppyscreen ]; then
              /etc/init.d/S99guppyscreen stop > /dev/null 2>&1
              killall -q guppyscreen > /dev/null 2>&1
            fi
            rm -rf /usr/data/guppyscreen
        elif [ -f /etc/init.d/S99guppyscreen ]; then
            # stop it for the last time before we migrate
            if grep -q "start-stop-daemon" /etc/init.d/S99guppyscreen; then
                /etc/init.d/S99guppyscreen stop > /dev/null 2>&1
                killall -q guppyscreen > /dev/null 2>&1
            fi
        fi

        GUPPY_BRANCH=$branch

        # we have logic here to force grumpyscreen to get updated to a minimum required version
        if [ -d /usr/data/guppyscreen ]; then
          TIMESTAMP=0
          if [ -f /usr/data/guppyscreen/release.info ]; then
            TIMESTAMP=$(cat /usr/data/guppyscreen/release.info | grep TIMESTAMP | awk -F '=' '{print $2}')
            if [ -z "$TIMESTAMP" ]; then
              TIMESTAMP=0
            fi
          fi

          GIT_BRANCH=$(cat /usr/data/guppyscreen/release.info | grep GIT_BRANCH | awk -F '=' '{print $2}')
          if [ -z "$GIT_BRANCH" ]; then
            GIT_BRANCH=main
          fi

          # force reinstall if switch branch mode
          if [ $TIMESTAMP -lt $GRUMPYSCREEN_TIMESTAMP ] || [ "$GIT_BRANCH" != "$GUPPY_BRANCH" ]; then
            echo
            echo "INFO: Forcing update of grumpyscreen"
            rm -rf /usr/data/guppyscreen
          fi
        fi

        if [ ! -d /usr/data/guppyscreen ]; then
            echo
            echo "INFO: Installing grumpyscreen ..."

            asset_name=guppyscreen.tar.gz
            # Ender 5 Max has a smaller screen
            if [ "$MODEL" = "F004" ] || [ "$MODEL" = "F005" ]; then
                asset_name=guppyscreen-smallscreen.tar.gz
            fi
            curl -L "https://github.com/pellcorp/guppyscreen/releases/download/${GUPPY_BRANCH}/${asset_name}" -o /usr/data/guppyscreen.tar.gz
            if [ $? -eq 0 ]; then
                tar xf /usr/data/guppyscreen.tar.gz -C /usr/data/ 2> /dev/null
                status=$?
                rm /usr/data/guppyscreen.tar.gz
                if [ $status -ne 0 ]; then
                    echo "ERROR: Grumpyscreen (branch ${GUPPY_BRANCH}) could not be downloaded!"
                    return 0
                fi
            else
                echo "ERROR: Grumpyscreen (branch ${GUPPY_BRANCH}) could not be downloaded!"
                return 0
            fi

            if [ "$MODEL" = "F005" ]; then
              /usr/data/pellcorp/tools/rotate-grumpyscreen.sh 0
            fi
        fi

        cp /usr/data/pellcorp/k1/services/S99guppyscreen /etc/init.d/ || exit $?

        ln -sf /usr/data/pellcorp/k1/files/respawn/libeinfo.so.1 /lib/libeinfo.so.1
        ln -sf /usr/data/pellcorp/k1/files/respawn/librc.so.1 /lib/librc.so.1

        if [ ! -d "/usr/lib/python3.8/site-packages/matplotlib-2.2.3-py3.8.egg-info" ]; then
            echo "WARNING: Not replacing mathplotlib ft2font module. PSD graphs might not work!"
        else
            cp /usr/data/pellcorp/k1/files/ft2font.cpython-38-mipsel-linux-gnu.so /usr/lib/python3.8/site-packages/matplotlib/ || exit $?
        fi

        # remove all excludes from grumpyscreen
        for file in gcode_shell_command.py guppy_config_helper.py calibrate_shaper_config.py guppy_module_loader.py tmcstatus.py; do
            if grep -q "klippy/extras/${file}" "/usr/data/klipper/.git/info/exclude"; then
                sed -i "/klippy\/extras\/$file$/d" "/usr/data/klipper/.git/info/exclude"
            fi
        done

        # get rid of the old guppyscreen config
        [ -d /usr/data/printer_data/config/GuppyScreen ] && rm -rf /usr/data/printer_data/config/GuppyScreen
        [ -f /usr/data/printer_data/config/guppyscreen.cfg ] && rm /usr/data/printer_data/config/guppyscreen.cfg

        if [ "$mode" != "switch-branch" ]; then
            echo "guppyscreen" >> /usr/data/pellcorp.done
        fi
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function setup_probe() {
    grep -q "probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up generic probe config ..."

        $CONFIG_HELPER --remove-section "bed_mesh" || exit $?
        $CONFIG_HELPER --remove-section-entry "stepper_z" "position_endstop" || exit $?
        $CONFIG_HELPER --replace-section-entry "stepper_z" "endstop_pin" "probe:z_virtual_endstop" || exit $?

        cp /usr/data/pellcorp/config/quickstart.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "quickstart.cfg" || exit $?

        # because we are using force move with 3mm, as a safety feature we will lower the position max
        # by 3mm ootb to avoid damaging the printer if you do a really big print
        position_max=$($CONFIG_HELPER --get-section-entry "stepper_z" "position_max" --minus 3 --integer)
        $CONFIG_HELPER --replace-section-entry "stepper_z" "position_max" "$position_max" || exit $?

        echo "probe" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function install_cartographer_klipper() {
    local mode=$1

    grep -q "cartographer-klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/cartographer-klipper ]; then
            rm -rf /usr/data/cartographer-klipper
        fi

        if [ ! -d /usr/data/cartographer-klipper ]; then
            echo
            echo "INFO: Installing cartographer-klipper ..."
            git clone https://github.com/pellcorp/cartographer-klipper.git /usr/data/cartographer-klipper || exit $?
        else
            cd /usr/data/cartographer-klipper
            REMOTE_URL=$(git remote get-url origin)
            if [ "$REMOTE_URL" != "https://github.com/pellcorp/cartographer-klipper.git" ]; then
                echo "INFO: Switching cartographer-klipper to pellcorp fork"
                git remote set-url origin https://github.com/pellcorp/cartographer-klipper.git
                git fetch origin
            fi

            branch=$(git rev-parse --abbrev-ref HEAD)
            # do not stuff up a different branch
            if [ "$branch" = "master" ]; then
                revision=$(git rev-parse --short HEAD)
                # reset our branch or update from v1.0.5
                if [ "$revision" = "303ea63" ] || [ "$revision" = "8324877" ]; then
                    echo "INFO: Forcing cartographer-klipper update"
                    git fetch origin
                    git reset --hard v1.1.0
                fi
            fi
        fi
        cd - > /dev/null

        echo
        echo "INFO: Running cartographer-klipper installer ..."
        bash /usr/data/cartographer-klipper/install.sh || exit $?
        ln -sf /usr/data/cartographer-klipper/ /root
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        echo "cartographer-klipper" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function install_beacon_klipper() {
    local mode=$1

    grep -q "beacon-klipper" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        if [ "$mode" != "update" ] && [ -d /usr/data/beacon-klipper ]; then
            rm -rf /usr/data/beacon-klipper
        fi

        if [ ! -d /usr/data/beacon-klipper ]; then
            echo
            echo "INFO: Installing beacon-klipper ..."
            git clone https://github.com/beacon3d/beacon_klipper /usr/data/beacon-klipper || exit $?
        fi

        /usr/data/pellcorp/k1/beacon-install.sh || return $?
        ln -sf /usr/data/beacon-klipper/ /root
        /usr/share/klippy-env/bin/python3 -m compileall /usr/data/klipper/klippy || exit $?

        echo "beacon-klipper" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function cleanup_probe() {
    local probe=$1

    if [ -f /usr/data/printer_data/config/${probe}_macro.cfg ]; then
        rm /usr/data/printer_data/config/${probe}_macro.cfg
    fi
    $CONFIG_HELPER --remove-include "${probe}_macro.cfg" || exit $?

    if [ "$probe" = "cartotouch" ] || [ "$probe" = "beacon" ]; then
        $CONFIG_HELPER --remove-section-entry "stepper_z" "homing_retract_dist" || exit $?
    fi

    if [ -f /usr/data/printer_data/config/$probe.cfg ]; then
        rm /usr/data/printer_data/config/$probe.cfg
    fi
    $CONFIG_HELPER --remove-include "$probe.cfg" || exit $?

    # if switching from btt eddy remove this file
    if [ "$probe" = "btteddy" ] && [ -f /usr/data/printer_data/config/variables.cfg ]; then
        rm /usr/data/printer_data/config/variables.cfg
    fi

    # we use the cartographer includes
    if [ "$probe" = "cartotouch" ]; then
        probe=cartographer
    elif [ "$probe" = "eddyng" ]; then
        probe=btteddy
    fi

    if [ -f /usr/data/printer_data/config/${probe}.conf ]; then
        rm /usr/data/printer_data/config/${probe}.conf
    fi

    $CONFIG_HELPER --file moonraker.conf --remove-include "${probe}.conf" || exit $?

    if [ -f /usr/data/printer_data/config/${probe}_calibrate.cfg ]; then
        rm /usr/data/printer_data/config/${probe}_calibrate.cfg
    fi
    $CONFIG_HELPER --remove-include "${probe}_calibrate.cfg" || exit $?

    if [ -f /usr/data/printer_data/config/$probe-${model}.cfg ]; then
        rm /usr/data/printer_data/config/$probe-${model}.cfg
    fi
    $CONFIG_HELPER --remove-include "$probe-${model}.cfg" || exit $?
}

function cleanup_probes() {
  cleanup_probe microprobe
  cleanup_probe btteddy
  cleanup_probe eddyng
  cleanup_probe cartotouch
  cleanup_probe beacon
  cleanup_probe klicky
  cleanup_probe bltouch
}

function setup_bltouch() {
    grep -q "bltouch-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up bltouch/crtouch/3dtouch ..."

        cleanup_probes

        cp /usr/data/pellcorp/config/bltouch.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "bltouch.cfg" || exit $?

        cp /usr/data/pellcorp/config/bltouch_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "bltouch_macro.cfg" || exit $?

        # need to add a empty bltouch section for baby stepping to work
        $CONFIG_HELPER --remove-section "bltouch" || exit $?
        $CONFIG_HELPER --add-section "bltouch" || exit $?
        z_offset=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry bltouch z_offset)
        if [ -n "$z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "bltouch" "# z_offset" "0.0" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "bltouch" "z_offset" "0.0" || exit $?
        fi

        echo "bltouch-probe" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function setup_microprobe() {
    grep -q "microprobe-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up microprobe ..."

        cleanup_probes

        cp /usr/data/pellcorp/config/microprobe.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "microprobe.cfg" || exit $?

        cp /usr/data/pellcorp/config/microprobe_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "microprobe_macro.cfg" || exit $?

        # remove previous directly imported microprobe config
        $CONFIG_HELPER --remove-section "output_pin probe_enable" || exit $?

        # need to add a empty probe section for baby stepping to work
        $CONFIG_HELPER --remove-section "probe" || exit $?
        $CONFIG_HELPER --add-section "probe" || exit $?
        z_offset=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry probe z_offset)
        if [ -n "$z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "probe" "# z_offset" "0.0" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "probe" "z_offset" "0.0" || exit $?
        fi

        echo "microprobe-probe" >> /usr/data/pellcorp.done
        sync

        # means klipper needs to be restarted
        return 1
    fi
    return 0
}

function setup_klicky() {
    grep -q "klicky-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up klicky ..."

        cleanup_probes

        cp /usr/data/pellcorp/config/klicky.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "klicky.cfg" || exit $?

        # need to add a empty probe section for baby stepping to work
        $CONFIG_HELPER --remove-section "probe" || exit $?
        $CONFIG_HELPER --add-section "probe" || exit $?
        z_offset=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry probe z_offset)
        if [ -n "$z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "probe" "# z_offset" "2.0" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "probe" "z_offset" "2.0" || exit $?
        fi

        cp /usr/data/pellcorp/config/klicky_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "klicky_macro.cfg" || exit $?

        echo "klicky-probe" >> /usr/data/pellcorp.done
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

function setup_cartotouch() {
    grep -q "cartotouch-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up cartotouch ..."

        cleanup_probes

        cp /usr/data/pellcorp/k1/cartographer.conf /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "cartographer.conf" || exit $?

        cp /usr/data/pellcorp/config/cartotouch_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartotouch_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp /usr/data/pellcorp/config/cartotouch.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "cartotouch.cfg" || exit $?

        y_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max" --divisor 2 --integer)
        x_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_max" --divisor 2 --integer)
        $CONFIG_HELPER --file cartotouch.cfg --replace-section-entry "bed_mesh" "zero_reference_position" "$x_position_mid,$y_position_mid" || exit $?

        set_serial_cartotouch

        # a slight change to the way cartotouch is configured
        $CONFIG_HELPER --remove-section "force_move" || exit $?

        # as we are referencing the included cartographer now we want to remove the included value
        # from any previous installation
        $CONFIG_HELPER --remove-section "scanner" || exit $?
        $CONFIG_HELPER --add-section "scanner" || exit $?

        scanner_touch_z_offset=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry scanner scanner_touch_z_offset)
        if [ -n "$scanner_touch_z_offset" ]; then
          $CONFIG_HELPER --replace-section-entry "scanner" "# scanner_touch_z_offset" "0.05" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "scanner" "scanner_touch_z_offset" "0.05" || exit $?
        fi

        scanner_mode=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry scanner mode)
        if [ -n "$scanner_mode" ]; then
            $CONFIG_HELPER --replace-section-entry "scanner" "# mode" "touch" || exit $?
        else
            $CONFIG_HELPER --replace-section-entry "scanner" "mode" "touch" || exit $?
        fi

        # Ender 5 Max we don't have firmware for it, so need to configure cartographer instead for adxl
        if [ "$MODEL" = "F004" ]; then
          # new versions of Ender 5 Max firmware added accel_chip_proxy to replace adxl
          $CONFIG_HELPER --add-section "adxl345"
          $CONFIG_HELPER --replace-section-entry "adxl345" "cs_pin" "scanner:PA3" || exit $?
          $CONFIG_HELPER --replace-section-entry "adxl345" "spi_bus" "spi1" || exit $?
          $CONFIG_HELPER --replace-section-entry "adxl345" "axes_map" "x,y,z" || exit $?
          $CONFIG_HELPER --remove-section-entry "adxl345" "spi_speed" || exit $?
          $CONFIG_HELPER --remove-section-entry "adxl345" "spi_software_sclk_pin" || exit $?
          $CONFIG_HELPER --remove-section-entry "adxl345" "spi_software_mosi_pin" || exit $?
          $CONFIG_HELPER --remove-section-entry "adxl345" "spi_software_miso_pin" || exit $?
          $CONFIG_HELPER --replace-section-entry "resonance_tester" "accel_chip" "adxl345" || exit $?
        fi

        echo "cartotouch-probe" >> /usr/data/pellcorp.done
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
    grep -q "beacon-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up beacon ..."

        cleanup_probes

        cp /usr/data/pellcorp/k1/beacon.conf /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --file moonraker.conf --add-include "beacon.conf" || exit $?

        cp /usr/data/pellcorp/config/beacon_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "beacon_macro.cfg" || exit $?

        $CONFIG_HELPER --replace-section-entry "stepper_z" "homing_retract_dist" "0" || exit $?

        cp /usr/data/pellcorp/config/beacon.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "beacon.cfg" || exit $?

        # for beacon can't use homing override
        $CONFIG_HELPER --file sensorless.cfg --remove-section "homing_override"

        y_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_max" --divisor 2 --integer)
        x_position_mid=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_max" --divisor 2 --integer)
        $CONFIG_HELPER --file beacon.cfg --replace-section-entry "beacon" "home_xy_position" "$x_position_mid,$y_position_mid" || exit $?
        $CONFIG_HELPER --file beacon.cfg --replace-section-entry "bed_mesh" "zero_reference_position" "$x_position_mid,$y_position_mid" || exit $?

        # for Ender 5 Max need to swap homing order for beacon
        if [ "$MODEL" = "F004" ]; then
            $CONFIG_HELPER --file beacon.cfg --replace-section-entry "beacon" "home_y_before_x" "True" || exit $?
        fi

        set_serial_beacon

        $CONFIG_HELPER --remove-section "beacon" || exit $?
        $CONFIG_HELPER --add-section "beacon" || exit $?

        beacon_cal_nozzle_z=$($CONFIG_HELPER --ignore-missing --file /usr/data/pellcorp-overrides/printer.cfg.save_config --get-section-entry beacon cal_nozzle_z)
        if [ -n "$beacon_cal_nozzle_z" ]; then
          $CONFIG_HELPER --replace-section-entry "beacon" "# cal_nozzle_z" "0.1" || exit $?
        else
          $CONFIG_HELPER --replace-section-entry "beacon" "cal_nozzle_z" "0.1" || exit $?
        fi

        # Ender 5 Max we don't have firmware for it, so need to configure cartographer instead for adxl
        if [ "$MODEL" = "F004" ]; then
          $CONFIG_HELPER --remove-section "adxl345" || exit $?
          $CONFIG_HELPER --replace-section-entry "resonance_tester" "accel_chip" "beacon" || exit $?
        fi

        echo "beacon-probe" >> /usr/data/pellcorp.done
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
    grep -q "btteddy-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up btteddy ..."

        cleanup_probes

        cp /usr/data/pellcorp/config/btteddy.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy.cfg" || exit $?

        set_serial_btteddy

        cp /usr/data/pellcorp/config/btteddy_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "btteddy_macro.cfg" || exit $?

        $CONFIG_HELPER --remove-section "probe_eddy_current btt_eddy" || exit $?
        $CONFIG_HELPER --add-section "probe_eddy_current btt_eddy" || exit $?

        echo "btteddy-probe" >> /usr/data/pellcorp.done
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
    grep -q "eddyng-probe" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        echo
        echo "INFO: Setting up btt eddy-ng ..."

        cleanup_probes

        cp /usr/data/pellcorp/config/eddyng.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "eddyng.cfg" || exit $?

        set_serial_eddyng

        cp /usr/data/pellcorp/config/eddyng_macro.cfg /usr/data/printer_data/config/ || exit $?
        $CONFIG_HELPER --add-include "eddyng_macro.cfg" || exit $?

        $CONFIG_HELPER --remove-section "probe_eddy_ng btt_eddy" || exit $?
        $CONFIG_HELPER --add-section "probe_eddy_ng btt_eddy" || exit $?

        echo "eddyng-probe" >> /usr/data/pellcorp.done
        sync
        return 1
    fi
    return 0
}

function install_entware() {
    local mode=$1
    if ! grep -q "entware" /usr/data/pellcorp.done; then
        echo
        /usr/data/pellcorp/k1/entware-install.sh "$mode" || exit $?

        echo "entware" >> /usr/data/pellcorp.done
        sync
    fi
}

function apply_overrides() {
    return_status=0
    grep -q "overrides" /usr/data/pellcorp.done
    if [ $? -ne 0 ]; then
        /usr/data/pellcorp/tools/apply-overrides.sh
        return_status=$?
        echo "overrides" >> /usr/data/pellcorp.done
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
    position_min_x=$($CONFIG_HELPER --get-section-entry "stepper_x" "position_min" --integer)
    position_min_y=$($CONFIG_HELPER --get-section-entry "stepper_y" "position_min" --integer)
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

    sync
    return $changed
}

function fix_custom_config() {
    changed=0
    custom_configs=$(find /usr/data/printer_data/config/ -type f -maxdepth 1 -exec grep -l "\[gcode_macro M109\]" {} \;)
    if [ -n "$custom_configs" ]; then
        for custom_config in $custom_configs; do
            filename=$(basename $custom_config)
            if [ "$filename" != "useful_macros.cfg" ]; then
                echo "INFO: Deleting M109 macro from $custom_config"
                $CONFIG_HELPER --file $filename --remove-section "gcode_macro M109"
                changed=1
            fi
        done
    fi
    custom_configs=$(find /usr/data/printer_data/config/ -type f -maxdepth 1 -exec grep -l "\[gcode_macro M190\]" {} \;)
    if [ -n "$custom_configs" ]; then
        for custom_config in $custom_configs; do
            filename=$(basename $custom_config)
            if [ "$filename" != "useful_macros.cfg" ]; then
                echo "INFO: Deleting M190 macro from $custom_config"
                $CONFIG_HELPER --file $filename --remove-section "gcode_macro M190"
                changed=1
            fi
        done
    fi
    sync
    return $changed
}

if [ -f /usr/data/pellcorp.done ] && [ ! -L /usr/share/klipper ]; then
    echo
    echo "ERROR: Switch to stock has been activated"
    echo "If you wish to return to SimpleAF you must run: "
    echo "  /usr/data/pellcorp/k1/switch-to-stock.sh --revert"
    echo
    exit 1
fi

# special mode to update the repo only
# this stuff we do not want to have a log file for
if [ "$1" = "--update-branch" ]; then
    update_repo /usr/data/pellcorp
    exit $?
elif [ "$1" = "--grumpy-branch" ]; then
    install_guppyscreen "switch-branch" "$2"
    if [ $? -ne 0 ]; then
        echo "INFO: Restarting Grumpyscreen ..."
        systemctl restart grumpyscreen
    fi
    exit 0
elif [ "$1" = "--branch" ] && [ -n "$2" ]; then # convenience for testing new features
    update_repo /usr/data/pellcorp $2 || exit $?
    exit $?
elif [ "$1" = "--cartographer-branch" ]; then
    shift
    if [ -d /usr/data/cartographer-klipper ]; then
        branch=master
        channel=stable
        if [ "$1" = "stable" ]; then
            branch=master
        elif [ "$1" = "beta" ]; then
            branch=beta
            channel=dev
        else
            branch=$1
            channel=dev
        fi
        update_repo /usr/data/cartographer-klipper $branch || exit $?
        update_klipper || exit $?
        if [ -f /usr/data/printer_data/config/cartographer.conf ]; then
            $CONFIG_HELPER --file cartographer.conf --replace-section-entry 'update_manager cartographer' channel $channel || exit $?
            $CONFIG_HELPER --file cartographer.conf --replace-section-entry 'update_manager cartographer' primary_branch $branch || exit $?
            restart_moonraker || exit $?
        fi
    else
        echo "Error cartographer-klipper repo does not exist"
        exit 1
    fi
    exit 0
elif [ "$1" = "--klipper-branch" ]; then # convenience for testing new features
    if [ -n "$2" ]; then
        update_repo /usr/data/klipper $2 || exit $?
        update_klipper || exit $?
        exit 0
    else
        echo "Error invalid branch specified"
        exit 1
    fi
elif [ "$1" = "--klipper-repo" ]; then # convenience for testing new features
    if [ -n "$2" ]; then
        klipper_repo=$2
        if [ "$klipper_repo" = "k1-carto-klipper" ]; then
            echo "ERROR: Switching to k1-carto-klipper is no longer supported"
            exit 1
        fi

        if [ -d /usr/data/klipper/.git ]; then
            cd /usr/data/klipper/
            remote_repo=$(git remote get-url origin | awk -F '/' '{print $NF}' | sed 's/.git//g')
            cd - > /dev/null
            if [ "$remote_repo" != "$klipper_repo" ]; then
                echo "INFO: Switching klipper from pellcorp/$remote_repo to pellcorp/${klipper_repo} ..."
                rm -rf /usr/data/klipper

                echo "$klipper_repo" > /usr/data/pellcorp.klipper
            fi
        fi

        if [ ! -d /usr/data/klipper ]; then
            git clone https://github.com/pellcorp/${klipper_repo}.git /usr/data/klipper || exit $?
            if [ -n "$3" ]; then
              cd /usr/data/klipper && git switch $3 && cd - > /dev/null
            fi
        else
            update_repo /usr/data/klipper $3 || exit $?
        fi

        update_klipper || exit $?
        exit 0
    else
        echo "Error invalid klipper repo specified"
        exit 1
    fi
fi

export TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE=/usr/data/printer_data/logs/installer-$TIMESTAMP.log

cd /usr/data/pellcorp
PELLCORP_GIT_SHA=$(git rev-parse HEAD)
cd - > /dev/null

PELLCORP_UPDATED_SHA=
if [ -f /usr/data/pellcorp.done ]; then
    PELLCORP_UPDATED_SHA=$(cat /usr/data/pellcorp.done | grep "installed_sha" | awk -F '=' '{print $2}')
fi

{
    # figure out what existing probe if any is being used
    probe=

    if [ -f /usr/data/printer_data/config/bltouch.cfg ]; then
        probe=bltouch
    elif [ -f /usr/data/printer_data/config/microprobe.cfg ]; then
        probe=microprobe
    elif [ -f /usr/data/printer_data/config/cartotouch.cfg ]; then
        probe=cartotouch
    elif [ -f /usr/data/printer_data/config/beacon.cfg ]; then
        probe=beacon
    elif [ -f /usr/data/printer_data/config/klicky.cfg ]; then
        probe=klicky
    elif [ -f /usr/data/printer_data/config/eddyng.cfg ]; then
        probe=eddyng
    elif [ -f /usr/data/printer_data/config/btteddy.cfg ]; then
        probe=btteddy
    elif grep -q "\[scanner\]" /usr/data/printer_data/config/printer.cfg; then
        probe=cartotouch
    elif [ -f /usr/data/printer_data/config/bltouch-${model}.cfg ]; then
        probe=bltouch
    elif [ -f /usr/data/printer_data/config/microprobe-${model}.cfg ]; then
        probe=microprobe
    elif [ -f /usr/data/printer_data/config/btteddy-${model}.cfg ]; then
        probe=btteddy
    fi

    mode=install
    force=false
    skip_overrides=false
    probe_switch=false
    mount=

    if [ -f /usr/data/pellcorp.done ]; then
        install_mount=$(cat /usr/data/pellcorp.done | grep "mount=" | awk -F '=' '{print $2}')
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
        elif [ "$1" = "--force" ]; then
          force=true
          shift
        elif [ "$1" = "microprobe" ] || [ "$1" = "bltouch" ] || [ "$1" = "beacon" ] || [ "$1" = "klicky" ] || [ "$1" = "cartotouch" ] || [ "$1" = "btteddy" ] || [ "$1" = "eddyng" ]; then
            if [ "$mode" = "fix-serial" ]; then
                echo "ERROR: Switching probes is not supported while trying to fix serial!"
                exit 1
            fi
            if [ -n "$probe" ] && [ "$1" != "$probe" ]; then
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

    if [ -z "$probe" ]; then
        echo "ERROR: You must specify a probe you want to configure"
        echo "One of: [microprobe, bltouch, cartotouch, btteddy, eddyng, beacon, klicky]"
        exit 1
    fi

    probe_model=${probe}
    if [ "$probe" = "cartotouch" ]; then
        probe_model=cartographer
    elif [ "$probe" = "eddyng" ]; then
        probe_model=btteddy
    fi

    echo "INFO: Mode is $mode"
    echo "INFO: Probe is $probe"

    if [ -n "$PELLCORP_UPDATED_SHA" ]; then
        if [ "$mode" = "install" ]; then
            echo
            echo "ERROR: Installation has already completed"
            if [ "$probe_switch" = "true" ]; then
              echo "Perhaps you meant to execute an --update instead!"
            elif [ "$PELLCORP_UPDATED_SHA" != "$PELLCORP_GIT_SHA" ]; then
              echo "Perhaps you meant to execute an --update or a --reinstall instead!"
              echo "  https://pellcorp.github.io/creality-wiki/updating/#updating"
              echo "  https://pellcorp.github.io/creality-wiki/updating/#reinstalling"
            fi
            echo
            exit 1
        elif [ "$mode" = "update" ] && [ "$PELLCORP_UPDATED_SHA" = "$PELLCORP_GIT_SHA" ] && [ "$probe_switch" != "true" ] && [ "$force" != "true" ] && [ -z "$mount" ]; then
            echo
            echo "ERROR: Installation is already up to date"
            echo "Perhaps you forgot to execute a --branch main first!"
            echo "  https://pellcorp.github.io/creality-wiki/updating/#updating"
            echo
            exit 1
        fi
    fi

    # don't try and validate a mount if all we are wanting to do is fix serial
    if [ "$mode" != "fix-serial" ]; then
      if [ -z "$mount" ] && [ -n "$install_mount" ] && [ "$probe_switch" != "true" ]; then
        # for a partial install where we selected a mount, we can grab it from the pellcorp.done file
        if [ "$mode" = "install" ]; then
          mount=$install_mount
        elif [ -f /usr/data/printer_data/config/${probe_model}-${model}.cfg ]; then
          # if we are about to migrate an older installation we need to force the reapplication of the mount overrides
          # mounts which might have had the same config as some default -k1 / -k1m config so there would have been
          # no mount overrides generated
          echo "WARNING: Enforcing mount overrides for mount $install_mount for migration"
          mount=$install_mount
        fi
      fi

      if [ -n "$mount" ]; then
          /usr/data/pellcorp/tools/apply-mount-overrides.sh --verify $probe $mount $model
          if [ $? -eq 0 ]; then
              echo "INFO: Mount is $mount"
          else
              exit 1
          fi
      elif [ "$skip_overrides" = "true" ] || [ "$mode" = "install" ] || [ "$mode" = "reinstall" ]; then
          echo "ERROR: Mount option must be specified"
          exit 1
      elif [ -f /usr/data/pellcorp.done ]; then
          if [ -z "$install_mount" ] || [ "$probe_switch" = "true" ]; then
              echo "ERROR: Mount option must be specified"
              exit 1
          else
              echo "INFO: Mount is $install_mount"
          fi
      fi
      echo
    fi

    if [ "$mode" = "fix-serial" ]; then
        if [ -f /usr/data/pellcorp.done ]; then
            if [ "$probe" = "cartotouch" ]; then
                set_serial_cartotouch
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
            /etc/init.d/S55klipper_service restart
        fi
        exit 0
    elif [ "$mode" = "fix-client-variables" ]; then
        if [ -f /usr/data/pellcorp.done ]; then
            fixup_client_variables_config
            fixup_client_variables_config=$?
            if [ $fixup_client_variables_config -ne 0 ]; then
                echo "INFO: Restarting Klipper ..."
                /etc/init.d/S55klipper_service restart
            else
                echo "INFO: No changes made"
            fi
            exit 0
        else
            echo "ERROR: No installation found"
            exit 1
        fi
    fi

    # to avoid cluttering the printer_data/config directory lets move stuff
    if [ -d /usr/data/printer_data/config/backups ] && [ ! -d /usr/data/backups ]; then
        mv /usr/data/printer_data/config/backups /usr/data/
    fi

    mkdir -p /usr/data/backups
    ln -sf /usr/data/backups /usr/data/printer_data/config/
    ln -sf /usr/data/backups/ /root

    mkdir -p /usr/data/pellcorp-overrides
    ln -sf /usr/data/pellcorp-overrides/ /root
    mkdir -p /usr/data/pellcorp-backups
    ln -sf /usr/data/pellcorp-backups/ /root

    # we don't do these kinds of backups anymore
    rm /usr/data/printer_data/config/*.bkp 2> /dev/null

    echo "INFO: Backing up existing configuration ..."
    if [ -f /etc/init.d/S99start_app ]; then
        # create a backup of creality config files
        if [ -f /usr/data/backups/creality-backup.tar.gz ]; then
            rm /usr/data/backups/creality-backup.tar.gz
        fi

        # note the filename format is intentional so that the cleanup service and backups tool ignores it
        cd /usr/data
        tar -zcf /usr/data/backups/creality-backup.tar.gz printer_data/config/*.cfg
        sync
        cd - > /dev/null
    else
        TIMESTAMP=${TIMESTAMP} /usr/data/pellcorp/tools/backups.sh --create
        echo
    fi

    mkdir -p /usr/data/pellcorp-backups
    # the pellcorp-backups do not need .pellcorp extension, so this is to fix backwards compatible
    if [ -f /usr/data/pellcorp-backups/printer.pellcorp.cfg ]; then
        mv /usr/data/pellcorp-backups/printer.pellcorp.cfg /usr/data/pellcorp-backups/printer.cfg
    fi

    # so if the installer has never been run we should grab a backup of the printer.cfg
    if [ ! -f /usr/data/pellcorp.done ] && [ ! -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
        # just to make sure we don't accidentally copy printer.cfg to backup if the backup directory
        # is deleted, add a stamp to config files to we can know for sure.
        if ! grep -q "# Modified by Simple AF " /usr/data/printer_data/config/printer.cfg; then
            cp /usr/data/printer_data/config/printer.cfg /usr/data/pellcorp-backups/printer.factory.cfg
            sed -i '/^#*#/d' /usr/data/pellcorp-backups/printer.factory.cfg
        else
          echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
          echo "WARNING: No pristine factory printer.cfg available - config overrides are disabled!"
          echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
        fi
    fi

    if [ "$skip_overrides" = "true" ]; then
        echo "INFO: Configuration overrides will not be saved or applied"
    fi

    install_config_updater

    # we want to disable creality services at the very beginning otherwise shit gets weird
    # if the crazy creality S55klipper_service is still copying files
    disable_creality_services

    # no point doing this if its a new installation
    if [ -f /usr/data/pellcorp.done ]; then
        # completely remove all iterations of zero SimpleAddon
        for dir in addons SimpleAddon; do
          if [ -d /usr/data/printer_data/config/$dir ]; then
            rm -rf /usr/data/printer_data/config/$dir
          fi
        done
        for file in save-zoffset.cfg eddycalibrate.cfg quickstart.cfg cartographer_calibrate.cfg btteddy_calibrate.cfg; do
          $CONFIG_HELPER --remove-include "SimpleAddon/$file"
          sync
        done
        $CONFIG_HELPER --remove-include "addons/*.cfg"
        sync
    fi

    if [ "$mode" = "reinstall" ] || [ "$mode" = "update" ]; then
        if [ "$skip_overrides" != "true" ]; then
            if [ -f /usr/data/pellcorp-backups/printer.cfg ]; then
                /usr/data/pellcorp/tools/config-overrides.sh
            elif [ -f /usr/data/pellcorp.done ]; then # for a factory reset this warning is superfluous
              echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
              echo "WARNING: No /usr/data/pellcorp-backups/printer.cfg - config overrides won't be generated!"
              echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
            fi
        fi

        if [ -f /usr/data/pellcorp.done ]; then
          rm /usr/data/pellcorp.done
        fi

        # if we took a post factory reset backup for a reinstall restore it now
        if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
            if grep -q "#*# <---------------------- SAVE_CONFIG ---------------------->" /usr/data/pellcorp-backups/printer.factory.cfg; then
                sed -i '/^#*#/d' /usr/data/pellcorp-backups/printer.factory.cfg
            fi

            cp /usr/data/pellcorp-backups/printer.factory.cfg /usr/data/printer_data/config/printer.cfg
            sed -i "1s/^/# Modified by Simple AF ${TIMESTAMP}\n/" /usr/data/printer_data/config/printer.cfg
        elif [ "$mode" = "update" ]; then
            echo "ERROR: Update mode is not available as pristine factory printer.cfg is missing"
            exit 1
        fi
    fi

    if [ ! -f /usr/data/pellcorp.done ]; then
        # we need a flag to know what mount we are using
        if [ -n "$mount" ]; then
            echo "mount=$mount" > /usr/data/pellcorp.done
        elif [ -n "$install_mount" ]; then
            echo "mount=$install_mount" > /usr/data/pellcorp.done
        fi
    fi

    # create a directory for pngs to go
    mkdir -p /usr/data/printer_data/config/images

    # add a service to take care of updating various config files if ip address changes
    cp /usr/data/pellcorp/k1/services/S96ipaddress /etc/init.d/

    if [ -L /usr/data/printer_data/logs/messages ]; then
      rm /usr/data/printer_data/logs/messages
    fi
    ln -sf /var/log/messages /usr/data/printer_data/logs/messages.log

    # lets make sure we are not stranded in some repo dir
    cd /root

    touch /usr/data/pellcorp.done
    sync

    install_entware $mode
    install_webcam $mode
    install_boot_display

    install_moonraker $mode
    install_moonraker=$?

    install_nginx $mode
    install_nginx=$?

    install_fluidd $mode
    install_fluidd=$?

    install_mainsail $mode
    install_mainsail=$?

    install_klipper $mode $probe
    install_klipper=$?

    install_cartographer_klipper=0
    install_beacon_klipper=0
    if [ "$probe" = "cartographer" ] || [ "$probe" = "cartotouch" ]; then
      install_cartographer_klipper $mode
      install_cartographer_klipper=$?
    elif [ "$probe" = "beacon" ]; then
      install_beacon_klipper $mode
      install_beacon_klipper=$?
    fi

    install_guppyscreen $mode "main"
    install_guppyscreen=$?

    setup_probe
    setup_probe=$?

    if [ "$probe" = "cartotouch" ]; then
        setup_cartotouch
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

    if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
        # we want a copy of the file before config overrides are re-applied so we can correctly generate diffs
        # against different generations of the original file
        for file in printer.cfg start_end.cfg fan_control.cfg $probe_model.conf spoolman.conf internal_macros.cfg useful_macros.cfg timelapse.conf moonraker.conf webcam.conf sensorless.cfg ${probe}_macro.cfg ${probe}.cfg; do
            if [ -f /usr/data/printer_data/config/$file ]; then
                cp /usr/data/printer_data/config/$file /usr/data/pellcorp-backups/$file
            fi
        done

        if [ -f /usr/data/guppyscreen/guppyscreen.json ]; then
          cp /usr/data/guppyscreen/guppyscreen.json /usr/data/pellcorp-backups/
        fi
    fi

    apply_overrides=0
    # there will be no support for generating pellcorp-overrides unless you have done a factory reset
    if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
        if [ "$skip_overrides" != "true" ]; then
            apply_overrides
            apply_overrides=$?
        fi
    fi

    apply_mount_overrides=0
    if [ -n "$mount" ]; then
        /usr/data/pellcorp/tools/apply-mount-overrides.sh $probe $mount $model
        apply_mount_overrides=$?
    fi

    # cleanup any M109 or M190 redefined
    fix_custom_config
    fix_custom_config=$?

    fixup_client_variables_config
    fixup_client_variables_config=$?
    if [ $fixup_client_variables_config -eq 0 ]; then
        echo "INFO: No changes made"
    fi

    /usr/data/pellcorp/k1/update-ip-address.sh
    update_ip_address=$?
    echo
    
    if [ $apply_overrides -ne 0 ] || [ $install_moonraker -ne 0 ] || [ $install_cartographer_klipper -ne 0 ] || [ $install_beacon_klipper -ne 0 ] || [ $update_ip_address -ne 0 ]; then
        echo "INFO: Restarting Moonraker ..."
        sudo systemctl restart moonraker
    fi

    if [ $install_moonraker -ne 0 ] || [ $install_nginx -ne 0 ] || [ $install_fluidd -ne 0 ] || [ $install_mainsail -ne 0 ]; then
        echo "INFO: Restarting Nginx ..."
        sudo systemctl restart nginx
    fi

    if [ $fix_custom_config -ne 0 ] || [ $fixup_client_variables_config -ne 0 ] || [ $apply_overrides -ne 0 ] || [ $apply_mount_overrides -ne 0 ] || [ $install_cartographer_klipper -ne 0 ] || [ $install_beacon_klipper -ne 0 ] || [ $install_klipper -ne 0 ] || [ $setup_probe -ne 0 ] || [ $setup_probe_specific -ne 0 ]; then
        echo "INFO: Restarting Klipper ..."
        sudo systemctl restart klipper
        sudo systemctl restart klipper_mcu
    fi

    if [ $apply_overrides -ne 0 ] || [ $install_guppyscreen -ne 0 ]; then
        echo "INFO: Restarting Grumpyscreen ..."
        sudo systemctl restart grumpyscreen
    fi

    echo
    /usr/data/pellcorp/k1/tools/check-firmware.sh

    echo "installed_sha=$PELLCORP_GIT_SHA" >> /usr/data/pellcorp.done
    sync

    exit 0
} 2>&1 | tee -a $LOG_FILE
