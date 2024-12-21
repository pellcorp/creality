#!/bin/sh

target=nightly
if [ -n "$1" ]; then
  target=$1
fi
curl -L "https://github.com/pellcorp/guppyscreen/releases/download/$target/guppyscreen.tar.gz" -o /usr/data/guppyscreen.tar.gz || exit $?
tar xf /usr/data/guppyscreen.tar.gz -C /usr/data/ || exit $?
rm /usr/data/guppyscreen.tar.gz
/etc/init.d/S99guppyscreen restart
