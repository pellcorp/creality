#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"
K1_DIR="$(dirname $CURRENT_DIR)"
ROOT_DIR="$(dirname $K1_DIR)"

curl -L "https://github.com/pellcorp/grumpyscreen/releases/download/main/guppyscreen.tar.gz" -o $ROOT_DIR/k1/packages/guppyscreen.tar.gz
curl -L "https://github.com/pellcorp/grumpyscreen/releases/download/main/guppyscreen-smallscreen.tar.gz" -o $ROOT_DIR/k1/packages/guppyscreen-smallscreen.tar.gz
curl -L "https://github.com/pellcorp/grumpyscreen/releases/download/main/guppyscreen-rpi.tar.gz" -o $ROOT_DIR/rpi/packages/guppyscreen-rpi.tar.gz
