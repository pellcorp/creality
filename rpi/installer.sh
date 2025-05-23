#!/bin/bash

if [ "$(whoami)" = "root" ]; then
  echo "FATAL: This installer must not be run as root"
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

BASEDIR=$HOME

# everything else in the script assumes its cloned to $BASEDIR/pellcorp
# so we must verify this or shit goes wrong
if [ "$(dirname $(readlink -f $0))" != "$BASEDIR/pellcorp/rpi" ]; then
  >&2 echo "ERROR: This git repo must be cloned to $BASEDIR/pellcorp/rpi"
  exit 1
fi

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

if [ "$1" = "--branch" ] && [ -n "$2" ]; then
    update_repo $BASEDIR/pellcorp $2 || exit $?
    exit $?
fi
