#!/bin/sh

BASEDIR=$HOME
CONFIG_TYPE=rpi
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
    CONFIG_TYPE=k1
fi
CONFIG_OVERRIDES="$BASEDIR/pellcorp/tools/config-overrides.py"

setup_git_repo() {
    if [ -d $BASEDIR/pellcorp-overrides ]; then
        cd $BASEDIR/pellcorp-overrides
        if ! git status > /dev/null 2>&1; then
          if [ $(ls | wc -l) -gt 0 ]; then
            cd - > /dev/null
            mv $BASEDIR/pellcorp-overrides $BASEDIR/pellcorp-overrides.$$
          else
            cd - > /dev/null
            rm -rf $BASEDIR/pellcorp-overrides/
          fi
        fi
    fi

    git clone "https://$GITHUB_USERNAME:$GITHUB_TOKEN@github.com/$GITHUB_USERNAME/$GITHUB_REPO.git" $BASEDIR/pellcorp-overrides || exit $?
    cd $BASEDIR/pellcorp-overrides || exit $?
    git config user.name "$GITHUB_USERNAME" || exit $?
    git config user.email "$EMAIL_ADDRESS" || exit $?

    if [ -z "$GITHUB_BRANCH" ]; then
        export GITHUB_BRANCH=main
    fi

    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" != "$GITHUB_BRANCH" ]; then
      git switch $GITHUB_BRANCH 2>/dev/null
      if [ $? -eq 0 ]; then
        echo "Switched to branch $GITHUB_BRANCH"
      else
        git switch --orphan $GITHUB_BRANCH
        echo "Switched to new branch $GITHUB_BRANCH"
      fi
    fi

    # is this a brand new repo, setup a simple readme as the first commit
    if [ $(ls | wc -l) -eq 0 ]; then
        echo "# simple af pellcorp-overrides" >> README.md
        echo "https://pellcorp.github.io/creality-wiki/config_overrides/#git-backups-for-configuration-overrides" >> README.md
        git add README.md || exit $?
        git commit -m "initial commit" || exit $?
        git branch -M $GITHUB_BRANCH || exit $?
        git push -u origin $GITHUB_BRANCH || exit $?
    fi

    # the rest of the script will actually push the changes if needed
    if [ -d $BASEDIR/pellcorp-overrides.$$ ]; then
        mv $BASEDIR/pellcorp-overrides.$$/* $BASEDIR/pellcorp-overrides/
        rm -rf $BASEDIR/pellcorp-overrides.$$
    fi
}

override_file() {
    local file=$1

    if [ -L "$BASEDIR/printer_data/config/$file" ]; then
        return 0
    fi

    overrides_file="$STAGING/$file"
    if [ -f "$BASEDIR/pellcorp/config/$file" ]; then
        original_file="$BASEDIR/pellcorp/config/$file"
    else
        original_file="$BASEDIR/pellcorp/${CONFIG_TYPE}/$file"
    fi
    updated_file="$BASEDIR/printer_data/config/$file"
    if [ "$file" = "moonraker.asvc" ]; then
      updated_file="$BASEDIR/printer_data/moonraker.asvc"
    fi
    
    if [ -f "$BASEDIR/pellcorp-backups/$file" ]; then
        original_file="$BASEDIR/pellcorp-backups/$file"
    elif [ "$file" = "guppyscreen.cfg" ]; then # old file ignore it
        return 0
    elif [ "$file" = "belts_calibration.cfg" ] || [ "$file" = "KlipperScreen.conf" ]; then
        return 0
    elif [ "$file" = "moonraker.asvc" ] || [ "$file" = "printer.cfg" ] || [ "$file" = "internal_macros.cfg" ] || [ "$file" = "useful_macros.cfg" ] || [ "$file" = "webcam.conf" ] || [ "$file" = "beacon.conf" ] || [ "$file" = "cartographer.conf" ] || [ "$file" = "moonraker.conf" ] || [ "$file" = "start_end.cfg" ] || [ "$file" = "fan_control.cfg" ] || [ "$file" = "webcam.ini" ]; then
        # this is just to catch those files where no pellcorp-backup exists
        return 0
    elif [ "$file" = "grumpyscreen.ini" ]; then
        # if this is the new overrides file then we can back it up otherwise ignore it
        grep -q "guppy_update_cmd" "$BASEDIR/printer_data/config/$file"
        if [ $? -ne 0 ]; then
          echo "INFO: Backing up $BASEDIR/printer_data/config/$file ..."
          cp "$BASEDIR/printer_data/config/$file" "$STAGING/" || exit $?
          return 0
        else
          echo "INFO: Skipping $BASEDIR/printer_data/config/$file"
          return 0
        fi
    elif [ ! -f "$BASEDIR/pellcorp/config/$file" ] && [ ! -f "$BASEDIR/pellcorp/${CONFIG_TYPE}/$file" ]; then
        if ! echo "$file" | grep -qE "printer([0-9]+).cfg"; then
            echo "INFO: Backing up $BASEDIR/printer_data/config/$file ..."
            cp "$BASEDIR/printer_data/config/$file" "$STAGING/" || exit $?
            return 0
        else
            return 0
        fi
    fi

    if [ "$file" = "printer.cfg" ]; then
      $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --exclude-sections bltouch,probe || exit $?

      # the printer.cfg will always be done last so if there is already a overrides file for bltouch or microprobe we don't need to do it again
      if [ -f $BASEDIR/printer_data/config/bltouch-${model}.cfg ] && [ ! -f $BASEDIR/printer_data/config/bltouch.cfg ] && [ ! -f $STAGING/bltouch.cfg ]; then
        overrides_file="$STAGING/bltouch.cfg"
        $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --include-sections bltouch || exit $?
      elif [ -f $BASEDIR/printer_data/config/microprobe-${model}.cfg ] && [ ! -f $BASEDIR/printer_data/config/microprobe.cfg ] && [ ! -f $STAGING/microprobe.cfg ]; then
          overrides_file="$STAGING/microprobe.cfg"
          $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --include-sections probe || exit $?
      fi
    elif [ "$file" = "moonraker.asvc" ]; then
      # thanks gemini for this magic incantation
      additions=$(awk 'NR==FNR {a[$0]=1; next} !a[$0]' "$original_file" "$updated_file")
      if [ -n "$additions" ]; then
        echo "INFO: Saving moonraker.asvc additions to $STAGING/moonraker.asvc"
        printf "%s\n" "$additions" > $overrides_file
      fi
    else
      $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" || exit $?

      # special handling if migrating back to nginx for webcam, this only happens when we run the tool before completing the
      # first update after migrating cos the /usr/data/pellcorp.ipaddress will be removed!
      if [ "$file" = "webcam.conf" ] && [ -f $STAGING/webcam.conf ] && [ -f /usr/data/pellcorp.ipaddress ]; then
        PREVIOUS_IP_ADDRESS=$(cat /usr/data/pellcorp.ipaddress 2> /dev/null)
        # in this case it was previously derived by the ipaddress service so clean them out so we can safely go back to nginx
        # however if someone has enabled the skip action, this means they are managing the webcam.conf themselves and we need
        # to retain their custom configuration
        if [ "$PREVIOUS_IP_ADDRESS" != "skip" ]; then
          sed -i '/stream_url/d' $STAGING/webcam.conf
          sed -i '/snapshot_url/d' $STAGING/webcam.conf
        fi
      fi
    fi

    # we renamed the SENSORLESS_PARAMS to hide it
    if [ -f $STAGING/sensorless.cfg ]; then
      # so this is for ancient
      sed -i 's/gcode_macro SENSORLESS_PARAMS/gcode_macro _SENSORLESS_PARAMS/g' $STAGING/sensorless.cfg
      # this caters for recent change
      sed -i 's/gcode_macro _SENSORLESS_PARAMS/gcode_macro _HOMING_PARAMS/g' $STAGING/sensorless.cfg
    elif [ -f $STAGING/homing_override.cfg ]; then
      # this is for rpi only
      sed -i 's/gcode_macro _SENSORLESS_PARAMS/gcode_macro _HOMING_PARAMS/g' $STAGING/homing_override.cfg
    elif [ -f $STAGING/KAMP_Settings.cfg ]; then
      # remove any overrides for these values which do not apply to Smart Park and Line Purge
      sed -i '/variable_verbose_enable/d' $STAGING/KAMP_Settings.cfg
      sed -i '/variable_mesh_margin/d' $STAGING/KAMP_Settings.cfg
      sed -i '/variable_fuzz_amount/d' $STAGING/KAMP_Settings.cfg
      sed -i '/variable_probe_dock_enable/d' $STAGING/KAMP_Settings.cfg
      sed -i '/variable_attach_macro/d' $STAGING/KAMP_Settings.cfg
      sed -i '/variable_detach_macro/d' $STAGING/KAMP_Settings.cfg
    fi

    if [ "$file" = "printer.cfg" ]; then
      saves=false
      # a printer.cfg saved by a Windows editor has CRLF line endings, which read -r keeps on every line
      cr=$(printf '\r')
      while IFS= read -r line; do
        line="${line%"$cr"}"
        if [ "$line" = "#*# <---------------------- SAVE_CONFIG ---------------------->" ]; then
          saves=true
          echo "" > $STAGING/printer.cfg.save_config
          echo "INFO: Saving save config state to $STAGING/printer.cfg.save_config"
        fi
        if [ "$saves" = "true" ]; then
          echo "$line" >> $STAGING/printer.cfg.save_config
        fi
      done < "$updated_file"
    fi
}

# make sure we are outside of the $BASEDIR/pellcorp-overrides directory
cd ~

if [ "$1" = "--help" ]; then
  echo "Use '$(basename $0) --repo' to create a new git repo in $BASEDIR/pellcorp-overrides"
  echo "Use '$(basename $0) --clean-repo' to create a new git repo in $BASEDIR/pellcorp-overrides and ignore local files"
  exit 0
elif [ "$1" = "--repo" ] || [ "$1" = "--clean-repo" ]; then
  if [ -n "$GITHUB_USERNAME" ] && [ -n "$EMAIL_ADDRESS" ] && [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        if [ -d $BASEDIR/pellcorp-overrides/.git ]; then
          echo "ERROR: Repo dir $BASEDIR/pellcorp-overrides/.git exists"
          exit 1
        fi

        if [ "$1" = "--clean-repo" ] && [ -d $BASEDIR/pellcorp-overrides ]; then
          echo "INFO: Deleting existing $BASEDIR/pellcorp-overrides"
          rm -rf $BASEDIR/pellcorp-overrides
        fi
        setup_git_repo
    else
        echo "You must define these environment variables:"
        echo "  GITHUB_USERNAME"
        echo "  EMAIL_ADDRESS"
        echo "  GITHUB_TOKEN"
        echo "  GITHUB_REPO"
        echo
        echo "Optionally if you want to use a branch other than 'main':"
        echo "  GITHUB_BRANCH"
        echo
        echo "https://pellcorp.github.io/creality-wiki/config_overrides/#git-backups-for-configuration-overrides"
        exit 1
    fi
else
  if [ $(grep "probe" $BASEDIR/pellcorp.done | wc -l) -lt 2 ]; then
    echo
    echo "ERROR: Previous partial installation detected, configuration overrides will not be generated"
    if [ $(ls $BASEDIR/pellcorp-overrides/ 2> /dev/null | grep -v "config.info" | wc -l) -gt 0 ]; then
        echo "INFO: Previous configuration overrides will be used instead"
    fi
    exit 1
  fi

  if [ ! -f $BASEDIR/pellcorp-backups/printer.cfg ]; then
      echo "ERROR: $BASEDIR/pellcorp-backups/printer.cfg missing"
      exit 1
  fi

  if [ -f $BASEDIR/pellcorp-overrides.cfg ]; then
      echo "ERROR: $BASEDIR/pellcorp-overrides.cfg exists!"
      exit 1
  fi

  if [ ! -f $BASEDIR/pellcorp.done ]; then
      echo "ERROR: No installation found"
      exit 1
  fi

  # Everything is generated into a staging directory first. The previous overrides are only replaced once every
  # step has succeeded, a failure anywhere leaves them as they were (the trap removes the staging directory).
  OVERRIDES="$BASEDIR/pellcorp-overrides"
  STAGING="$BASEDIR/pellcorp-overrides.staging.$$"
  rm -rf "$STAGING" "$STAGING.list"
  mkdir -p "$STAGING" || exit $?
  trap 'rm -rf "$STAGING" "$STAGING.list"' EXIT

  # special case for moonraker.secrets
  if [ -f $BASEDIR/printer_data/moonraker.secrets ] && [ -f $BASEDIR/pellcorp/config/moonraker.secrets ]; then
      diff $BASEDIR/printer_data/moonraker.secrets $BASEDIR/pellcorp/config/moonraker.secrets > /dev/null
      if [ $? -ne 0 ]; then
          echo "INFO: Backing up $BASEDIR/printer_data/moonraker.secrets..."
          cp $BASEDIR/printer_data/moonraker.secrets "$STAGING/" || exit $?
      fi
  fi

  if [ -f $BASEDIR/guppyscreen/calibration.json ]; then
    echo "INFO: Saving grumpyscreen calibration.json to $OVERRIDES/calibration.json"
    cp $BASEDIR/guppyscreen/calibration.json "$STAGING/" || exit $?
    sync
  elif [ -f $BASEDIR/grumpyscreen/calibration.json ]; then
    echo "INFO: Saving grumpyscreen calibration.json to $OVERRIDES/calibration.json"
    cp $BASEDIR/grumpyscreen/calibration.json "$STAGING/" || exit $?
    sync
  fi

  # read the list line by line (not word split) so file names with spaces survive, the loop runs in this shell
  # (not a pipeline) so an exit in override_file really stops the script
  find "$BASEDIR/printer_data/config/" -maxdepth 1 ! -name 'printer-*.cfg' -a ! -name ".printer.cfg" -a -name "*.cfg" -o -name "*.conf" -o -name "*.ini" > "$STAGING.list" || exit $?
  while IFS= read -r config_path; do
    file=$(basename "$config_path")
    if [ "$file" != "printer.cfg" ]; then
      override_file "$file"
    fi
  done < "$STAGING.list"

  # we want the printer.cfg to be done last
  override_file printer.cfg

  if [ "$CONFIG_TYPE" = "rpi" ]; then
    # this is a special case
    override_file moonraker.asvc
  fi

  # every step worked: replace the previous generated overrides (config.info, README, .git etc stay)
  mkdir -p "$OVERRIDES" || exit $?
  rm -f "$OVERRIDES"/*.cfg "$OVERRIDES"/*.ini "$OVERRIDES"/*.conf "$OVERRIDES"/*.json "$OVERRIDES"/moonraker.asvc "$OVERRIDES"/printer.cfg.save_config "$OVERRIDES"/moonraker.secrets
  for generated in "$STAGING"/*; do
    [ -e "$generated" ] || continue
    mv -f "$generated" "$OVERRIDES/" || exit $?
  done
fi

cd $BASEDIR/pellcorp-overrides
if git status > /dev/null 2>&1; then
    echo
    echo "INFO: $BASEDIR/pellcorp-overrides is a git repository"

    # special handling for moonraker.secrets, we do not want to source control this
    # file for fear of leaking credentials
    if [ ! -f .gitignore ]; then
      echo "moonraker.secrets" > .gitignore
    elif ! grep -q "moonraker.secrets" .gitignore; then
      echo "moonraker.secrets" >> .gitignore
    fi

    # make sure we remove any versioned file
    git rm --cached moonraker.secrets 2> /dev/null

    status=$(git status)
    echo "$status" | grep -q "nothing to commit, working tree clean"
    if [ $? -eq 0 ]; then
        echo "INFO: No changes in git repository"
    else
        echo "INFO: Outstanding changes - pushing them to remote repository"
        branch=$(git rev-parse --abbrev-ref HEAD)
        git add --all || exit $?
        git commit -m "pellcorp override changes" || exit $?
        git push -u origin $branch || exit $?
    fi
fi
