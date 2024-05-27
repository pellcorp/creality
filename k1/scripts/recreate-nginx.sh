#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"

wget https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz -O /tmp/moonraker.tar.gz
tar -zxvf /tmp/moonraker.tar.gz -C /tmp nginx
rm /tmp/moonraker.tar.gz
pushd /tmp
tar -zcf $CURRENT_DIR/nginx.tar.gz nginx || exit $?
