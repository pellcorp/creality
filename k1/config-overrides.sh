#!/bin/sh

CONFIG_OVERRIDES="/usr/data/pellcorp/k1/config-overrides.py"

MODEL=$(/usr/bin/get_sn_mac.sh model)
if [ "$MODEL" = "CR-K1" ] || [ "$MODEL" = "K1C" ] || [ "$MODEL" = "K1 SE" ]; then
    model=k1
elif [ "$MODEL" = "CR-K1 Max" ] || [ "$MODEL" = "K1 Max SE" ]; then
    model=k1m
elif [ "$MODEL" = "F004" ]; then
    model=f004
else
    echo "This script is not supported for $MODEL!"
    exit 1
fi

setup_git_repo() {
    if [ -d /usr/data/pellcorp-overrides ]; then
        cd /usr/data/pellcorp-overrides
        if ! git status > /dev/null 2>&1; then
          if [ $(ls | wc -l) -gt 0 ]; then
            cd - > /dev/null
            mv /usr/data/pellcorp-overrides /usr/data/pellcorp-overrides.$$
          else
            cd - > /dev/null
            rm -rf /usr/data/pellcorp-overrides/
          fi
        fi
    fi

    git clone "https://$GITHUB_USERNAME:$GITHUB_TOKEN@github.com/$GITHUB_USERNAME/$GITHUB_REPO.git" /usr/data/pellcorp-overrides || exit $?
    cd /usr/data/pellcorp-overrides || exit $?
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
    if [ -d /usr/data/pellcorp-overrides.$$ ]; then
        mv /usr/data/pellcorp-overrides.$$/* /usr/data/pellcorp-overrides/
        rm -rf /usr/data/pellcorp-overrides.$$
    fi
}

override_file() {
    local file=$1

    if [ -L /usr/data/printer_data/config/$file ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    fi

    overrides_file="/usr/data/pellcorp-overrides/$file"
    original_file="/usr/data/pellcorp/k1/$file"
    updated_file="/usr/data/printer_data/config/$file"
    
    if [ -f "/usr/data/pellcorp-backups/$file" ]; then
        original_file="/usr/data/pellcorp-backups/$file"
    elif [ "$file" = "guppyscreen.cfg" ] || [ "$file" = "internal_macros.cfg" ] || [ "$file" = "useful_macros.cfg" ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ "$file" = "printer.cfg" ] || [ "$file" = "beacon.conf" ] || [ "$file" = "cartographer.conf" ] || [ "$file" = "moonraker.conf" ] || [ "$file" = "start_end.cfg" ] || [ "$file" = "fan_control.cfg" ]; then
        # for printer.cfg, useful_macros.cfg, start_end.cfg, fan_control.cfg and moonraker.conf - there must be an pellcorp-backups file
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ ! -f "/usr/data/pellcorp/k1/$file" ]; then
        if ! echo $file | grep -qE "printer([0-9]+).cfg"; then
            echo "INFO: Backing up /usr/data/printer_data/config/$file ..."
            cp  /usr/data/printer_data/config/$file /usr/data/pellcorp-overrides/
            return 0
        else
            echo "INFO: Ignoring /usr/data/printer_data/config/$file ..."
            return 0
        fi
    fi
    if [ "$file" = "printer.cfg" ]; then
      $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --exclude-sections bltouch,probe || exit $?

      # the printer.cfg will always be done last so if there is already a overrides file for bltouch or microprobe we don't need to do it again
      if [ -f /usr/data/printer_data/config/bltouch-${model}.cfg ] && [ ! -f /usr/data/printer_data/config/bltouch.cfg ] && [ ! -f /usr/data/pellcorp-overrides/bltouch.cfg ]; then
        overrides_file="/usr/data/pellcorp-overrides/bltouch.cfg"
        $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --include-sections bltouch || exit $?
      elif [ -f /usr/data/printer_data/config/microprobe-${model}.cfg ] && [ ! -f /usr/data/printer_data/config/microprobe.cfg ] && [ ! -f /usr/data/pellcorp-overrides/microprobe.cfg ]; then
          overrides_file="/usr/data/pellcorp-overrides/microprobe.cfg"
          $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" --include-sections probe || exit $?
      fi
    else
      $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" || exit $?
    fi

    # we renamed the SENSORLESS_PARAMS to hide it
    if [ -f /usr/data/pellcorp-overrides/sensorless.cfg ]; then
      sed -i 's/gcode_macro SENSORLESS_PARAMS/gcode_macro _SENSORLESS_PARAMS/g' /usr/data/pellcorp-overrides/sensorless.cfg
    elif [ -f /usr/data/pellcorp-overrides/KAMP_Settings.cfg ]; then
      # remove any overrides for these values which do not apply to Smart Park and Line Purge
      sed -i '/variable_verbose_enable/d' /usr/data/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_mesh_margin/d' /usr/data/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_fuzz_amount/d' /usr/data/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_probe_dock_enable/d' /usr/data/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_attach_macro/d' /usr/data/pellcorp-overrides/KAMP_Settings.cfg
      sed -i '/variable_detach_macro/d' /usr/data/pellcorp-overrides/KAMP_Settings.cfg
    fi

    if [ "$file" = "printer.cfg" ]; then
      saves=false
      while IFS= read -r line; do
        if [ "$line" = "#*# <---------------------- SAVE_CONFIG ---------------------->" ]; then
          saves=true
          echo "" > /usr/data/pellcorp-overrides/printer.cfg.save_config
          echo "INFO: Saving save config state to /usr/data/pellcorp-overrides/printer.cfg.save_config"
        fi
        if [ "$saves" = "true" ]; then
          echo "$line" >> /usr/data/pellcorp-overrides/printer.cfg.save_config
        fi
      done < "$updated_file"
    fi
}

# make sure we are outside of the /usr/data/pellcorp-overrides directory
cd /root/

if [ "$1" = "--help" ]; then
  echo "Use '$(basename $0) --repo' to create a new git repo in /usr/data/pellcorp-overrides"
  echo "Use '$(basename $0) --clean-repo' to create a new git repo in /usr/data/pellcorp-overrides and ignore local files"
  exit 0
elif [ "$1" = "--repo" ] || [ "$1" = "--clean-repo" ]; then
  if [ -n "$GITHUB_USERNAME" ] && [ -n "$EMAIL_ADDRESS" ] && [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        if [ -d /usr/data/pellcorp-overrides/.git ]; then
          echo "ERROR: Repo dir /usr/data/pellcorp-overrides/.git exists"
          exit 1
        fi

        if [ "$1" = "--clean-repo" ] && [ -d /usr/data/pellcorp-overrides ]; then
          echo "INFO: Deleting existing /usr/data/pellcorp-overrides"
          rm -rf /usr/data/pellcorp-overrides
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
  if [ -f /usr/data/pellcorp-backups/printer.factory.cfg ]; then
      # the pellcorp-backups do not need .pellcorp extension, so this is to fix backwards compatible
      if [ -f /usr/data/pellcorp-backups/printer.pellcorp.cfg ]; then
          mv /usr/data/pellcorp-backups/printer.pellcorp.cfg /usr/data/pellcorp-backups/printer.cfg
      fi
  fi

  if [ ! -f /usr/data/pellcorp-backups/printer.cfg ]; then
      echo "ERROR: /usr/data/pellcorp-backups/printer.cfg missing"
      exit 1
  fi

  if [ -f /usr/data/pellcorp-overrides.cfg ]; then
      echo "ERROR: /usr/data/pellcorp-overrides.cfg exists!"
      exit 1
  fi

  if [ ! -f /usr/data/pellcorp.done ]; then
      echo "ERROR: No installation found"
      exit 1
  fi

  if [ $(grep "probe" /usr/data/pellcorp.done | wc -l) -lt 2 ]; then
    echo "ERROR: Previous partial installation detected, configuration overrides will not be generated"
    if [ -d /usr/data/pellcorp-overrides ]; then
        echo "INFO: Previous configuration overrides will be used instead"
    fi
    exit 1
  fi

  mkdir -p /usr/data/pellcorp-overrides

  # in case we changed config and no longer need an override file, we should delete all
  # all the config files there.
  rm /usr/data/pellcorp-overrides/*.cfg 2> /dev/null
  rm /usr/data/pellcorp-overrides/*.conf 2> /dev/null
  rm /usr/data/pellcorp-overrides/*.json 2> /dev/null
  if [ -f /usr/data/pellcorp-overrides/printer.cfg.save_config ]; then
    rm /usr/data/pellcorp-overrides/printer.cfg.save_config
  fi
  if [ -f /usr/data/pellcorp-overrides/moonraker.secrets ]; then
    rm /usr/data/pellcorp-overrides/moonraker.secrets
  fi

  # special case for moonraker.secrets
  if [ -f /usr/data/printer_data/moonraker.secrets ] && [ -f /usr/data/pellcorp/k1/moonraker.secrets ]; then
      diff /usr/data/printer_data/moonraker.secrets /usr/data/pellcorp/k1/moonraker.secrets > /dev/null
      if [ $? -ne 0 ]; then
          echo "INFO: Backing up /usr/data/printer_data/moonraker.secrets..."
          cp /usr/data/printer_data/moonraker.secrets /usr/data/pellcorp-overrides/
      fi
  fi

  files=$(find /usr/data/printer_data/config/ -maxdepth 1 ! -name 'printer-*.cfg' -a ! -name ".printer.cfg" -a -name "*.cfg" -o -name "*.conf")
  for file in $files; do
    file=$(basename $file)
    if [ "$file" != "printer.cfg" ]; then
      override_file $file
    fi
  done
  # we want the printer.cfg to be done last
  override_file printer.cfg

  /usr/data/pellcorp/k1/update-guppyscreen.sh --config-overrides
fi

cd /usr/data/pellcorp-overrides
if git status > /dev/null 2>&1; then
    echo
    echo "INFO: /usr/data/pellcorp-overrides is a git repository"

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
