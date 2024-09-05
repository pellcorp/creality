#!/bin/sh

CONFIG_OVERRIDES="/usr/data/pellcorp/k1/config-overrides.py"

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

    # is this a brand new repo, setup a simple readme as the first commit
    if [ $(ls | wc -l) -eq 0 ]; then
        echo "# simple af pellcorp-overrides" >> README.md
        echo "https://github.com/pellcorp/creality/wiki/K1-Stock-Mainboard-Less-Creality#git-backups-for-configuration-overrides" >> README.md
        git add README.md || exit $?
        git commit -m "initial commit" || exit $?
        git branch -M main || exit $?
        git push -u origin main || exit $?
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
    elif [ "$file" = "printer.cfg" ] || [ "$file" = "moonraker.conf" ]; then
        # for printer.cfg and moonraker.conf - there must be an pellcorp-backups file
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ "$file" = "guppyscreen.cfg" ] || [ "$file" = "fan_control.cfg" ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ ! -f "/usr/data/pellcorp/k1/$file" ]; then
        echo "INFO: Backing up /usr/data/printer_data/config/$file ..."
        cp  /usr/data/printer_data/config/$file /usr/data/pellcorp-overrides/
        return 0
    fi
    $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" || exit $?

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

if [ "$1" = "--repo" ] || [ "$1" = "--clean-repo" ]; then
  if [ -n "$GITHUB_USERNAME" ] && [ -n "$EMAIL_ADDRESS" ] && [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        if [ "$1" = "--clean-repo" ] && [ -d /usr/data/pellcorp-overrides ]; then
          echo "INFO: Deleting existing /usr/data/pellcorp-overrides"
          rm -rf /usr/data/pellcorp-overrides
        fi
        setup_git_repo
    else
        echo "You must define these environment variables:"
        echo "GITHUB_USERNAME"
        echo "EMAIL_ADDRESS"
        echo "GITHUB_TOKEN"
        echo "GITHUB_REPO"
        echo ""
        echo "https://github.com/pellcorp/creality/wiki/K1-Stock-Mainboard-Less-Creality#git-backups-for-configuration-overrides"
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

  mkdir -p /usr/data/pellcorp-overrides

  # in case we changed config and no longer need an override file, we should delete all
  # all the config files there.
  rm /usr/data/pellcorp-overrides/*.cfg 2> /dev/null
  rm /usr/data/pellcorp-overrides/*.conf 2> /dev/null
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

  files=$(find /usr/data/printer_data/config/ -maxdepth 1! -name 'printer-*.cfg' -a ! -name ".printer.cfg" -a -name "*.cfg" -o -name "*.conf")
  for file in $files; do
    file=$(basename $file)
    override_file $file
  done
fi

cd /usr/data/pellcorp-overrides
if git status > /dev/null 2>&1; then
    echo "INFO: /usr/data/pellcorp-overrides is a git repository"
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
