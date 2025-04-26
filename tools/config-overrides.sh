#!/bin/sh

BASEDIR=/home/pi
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

override_guppyscreen() {
    if [ -f $BASEDIR/pellcorp-backups/guppyscreen.json ] && [ -f $BASEDIR/guppyscreen/guppyscreen.json ]; then
        [ -f $BASEDIR/pellcorp-overrides/guppyscreen.json ] && rm $BASEDIR/pellcorp-overrides/guppyscreen.json
        for entry in display_brightness invert_z_icon display_sleep_sec theme touch_calibration_coeff; do
            stock_value=$(jq -cr ".$entry" $BASEDIR/pellcorp-backups/guppyscreen.json)
            new_value=$(jq -cr ".$entry" $BASEDIR/guppyscreen/guppyscreen.json)
            # you know what its not an actual json file its just the properties we support updating
            if [ "$entry" = "touch_calibration_coeff" ] && [ "$new_value" != "null" ]; then
                echo "$entry=$new_value" >> $BASEDIR/pellcorp-overrides/guppyscreen.json
            elif [ "$stock_value" != "null" ] && [ "$new_value" != "null" ] && [ "$stock_value" != "$new_value" ]; then
                echo "$entry=$new_value" >> $BASEDIR/pellcorp-overrides/guppyscreen.json
            fi
        done
        if [ -f $BASEDIR/pellcorp-overrides/guppyscreen.json ]; then
            echo "INFO: Saving overrides to $BASEDIR/pellcorp-overrides/guppyscreen.json"
            sync
        fi
    fi
}

override_file() {
    local file=$1

    if [ -L $BASEDIR/printer_data/config/$file ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    fi

    overrides_file="$BASEDIR/pellcorp-overrides/$file"
    if [ -f $BASEDIR/pellcorp/config/$file ]; then
        original_file="$BASEDIR/pellcorp/config/$file"
    else
        original_file="$BASEDIR/pellcorp/${CONFIG_TYPE}/$file"
    fi
    updated_file="$BASEDIR/printer_data/config/$file"
    
    if [ -f "$BASEDIR/pellcorp-backups/$file" ]; then
        original_file="$BASEDIR/pellcorp-backups/$file"
    elif [ "$file" = "guppyscreen.cfg" ]; then # old file ignore it
        return 0
    elif [ "$file" = "belts_calibration.cfg" ] || [ "$file" = "internal_macros.cfg" ] || [ "$file" = "useful_macros.cfg" ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ "$file" = "printer.cfg" ] || [ "$file" = "beacon.conf" ] || [ "$file" = "cartographer.conf" ] || [ "$file" = "moonraker.conf" ] || [ "$file" = "start_end.cfg" ] || [ "$file" = "fan_control.cfg" ]; then
        # for printer.cfg, useful_macros.cfg, start_end.cfg, fan_control.cfg and moonraker.conf - there must be an pellcorp-backups file
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ ! -f "$BASEDIR/pellcorp/config/$file" ] && [ ! -f "$BASEDIR/pellcorp/${CONFIG_TYPE}/$file" ]; then
        if ! echo $file | grep -qE "printer([0-9]+).cfg"; then
            echo "INFO: Backing up $BASEDIR/printer_data/config/$file ..."
            cp $BASEDIR/printer_data/config/$file $BASEDIR/pellcorp-overrides/
            return 0
        else
            echo "INFO: Ignoring $BASEDIR/printer_data/config/$file ..."
            return 0
        fi
    fi
    if [ "$file" = "printer.cfg" ]; then
      $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --exclude-sections bltouch,probe || exit $?

      # the printer.cfg will always be done last so if there is already a overrides file for bltouch or microprobe we don't need to do it again
      if [ -f $BASEDIR/printer_data/config/bltouch-${model}.cfg ] && [ ! -f $BASEDIR/printer_data/config/bltouch.cfg ] && [ ! -f $BASEDIR/pellcorp-overrides/bltouch.cfg ]; then
        overrides_file="$BASEDIR/pellcorp-overrides/bltouch.cfg"
        $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --include-sections bltouch || exit $?
      elif [ -f $BASEDIR/printer_data/config/microprobe-${model}.cfg ] && [ ! -f $BASEDIR/printer_data/config/microprobe.cfg ] && [ ! -f $BASEDIR/pellcorp-overrides/microprobe.cfg ]; then
          overrides_file="$BASEDIR/pellcorp-overrides/microprobe.cfg"
          $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --include-sections probe || exit $?
      fi
    else
      $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" || exit $?
    fi

    # we renamed the SENSORLESS_PARAMS to hide it
    if [ -f $BASEDIR/pellcorp-overrides/sensorless.cfg ]; then
      sed -i 's/gcode_macro SENSORLESS_PARAMS/gcode_macro _SENSORLESS_PARAMS/g' $BASEDIR/pellcorp-overrides/sensorless.cfg
    elif [ -f $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg ]; then
      # remove any overrides for these values which do not apply to Smart Park and Line Purge
      sed -i '/variable_verbose_enable/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_mesh_margin/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_fuzz_amount/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_probe_dock_enable/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_attach_macro/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_detach_macro/d' $BASEDIR/pellcorp-overrides/KAMP_Settings.cfg
    fi

    if [ "$file" = "printer.cfg" ]; then
      saves=false
      while IFS= read -r line; do
        if [ "$line" = "#*# <---------------------- SAVE_CONFIG ---------------------->" ]; then
          saves=true
          echo "" > $BASEDIR/pellcorp-overrides/printer.cfg.save_config
          echo "INFO: Saving save config state to $BASEDIR/pellcorp-overrides/printer.cfg.save_config"
        fi
        if [ "$saves" = "true" ]; then
          echo "$line" >> $BASEDIR/pellcorp-overrides/printer.cfg.save_config
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
  # there will be no support for generating pellcorp-overrides unless you have done a factory reset
  if [ -f $BASEDIR/pellcorp-backups/printer.factory.cfg ]; then
      # the pellcorp-backups do not need .pellcorp extension, so this is to fix backwards compatible
      if [ -f $BASEDIR/pellcorp-backups/printer.pellcorp.cfg ]; then
          mv $BASEDIR/pellcorp-backups/printer.pellcorp.cfg $BASEDIR/pellcorp-backups/printer.cfg
      fi
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

  if [ $(grep "probe" $BASEDIR/pellcorp.done | wc -l) -lt 2 ]; then
    echo "ERROR: Previous partial installation detected, configuration overrides will not be generated"
    if [ -d $BASEDIR/pellcorp-overrides ]; then
        echo "INFO: Previous configuration overrides will be used instead"
    fi
    exit 1
  fi

  mkdir -p $BASEDIR/pellcorp-overrides

  # in case we changed config and no longer need an override file, we should delete all
  # all the config files there.
  rm $BASEDIR/pellcorp-overrides/*.cfg 2> /dev/null
  rm $BASEDIR/pellcorp-overrides/*.conf 2> /dev/null
  rm $BASEDIR/pellcorp-overrides/*.json 2> /dev/null
  if [ -f $BASEDIR/pellcorp-overrides/printer.cfg.save_config ]; then
    rm $BASEDIR/pellcorp-overrides/printer.cfg.save_config
  fi
  if [ -f $BASEDIR/pellcorp-overrides/moonraker.secrets ]; then
    rm $BASEDIR/pellcorp-overrides/moonraker.secrets
  fi

  # special case for moonraker.secrets
  if [ -f $BASEDIR/printer_data/moonraker.secrets ] && [ -f $BASEDIR/pellcorp/config/moonraker.secrets ]; then
      diff $BASEDIR/printer_data/moonraker.secrets $BASEDIR/pellcorp/config/moonraker.secrets > /dev/null
      if [ $? -ne 0 ]; then
          echo "INFO: Backing up $BASEDIR/printer_data/moonraker.secrets..."
          cp $BASEDIR/printer_data/moonraker.secrets $BASEDIR/pellcorp-overrides/
      fi
  fi

  files=$(find $BASEDIR/printer_data/config/ -maxdepth 1 ! -name 'printer-*.cfg' -a ! -name ".printer.cfg" -a -name "*.cfg" -o -name "*.conf")
  for file in $files; do
    file=$(basename $file)
    if [ "$file" != "printer.cfg" ]; then
      override_file $file
    fi
  done
  # we want the printer.cfg to be done last
  override_file printer.cfg

  override_guppyscreen
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
