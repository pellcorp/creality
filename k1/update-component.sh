#!/bin/sh

component=$1
if [ -z "$component" ]; then
  echo "Component not specified"
  exit 1
fi

if [ ! -d /usr/data/pellcorp.done ]; then
  echo "Installation not found"
  exit 2
fi

sed -i "/$component/d" /usr/data/pellcorp.done
/usr/data/pellcorp/k1/installer.sh --install
