#!/bin/bash

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"
K1_DIR="$(dirname $SCRIPTS_DIR)"

# not sure this is necessary but I want to use the same version of python to update the env
if [ ! /usr/bin/python3.8 ]; then
    echo "Need python 3.8"
    exit 1
fi

sudo mkdir -p /usr/data
sudo chown -R $USER /usr/data

if [ -d /usr/data/moonraker-env ]; then
    rm -rf /usr/data/moonraker-env
fi
tar -zxf $K1_DIR/moonraker-env.tar.gz -C /usr/data || exit $?

file /usr/data/moonraker-env/bin/python3 | grep -q MIPS
if [ $? -ne 0 ]; then
    echo "The python3 is not MIPS aborting"
    exit 1
fi

# the env was originally for /usr/share/moonraker-env
sed -i 's:/usr/share/:/usr/data/:g' /usr/data/moonraker-env/bin/activate
sed -i 's:/usr/share/:/usr/data/:g' /usr/data/moonraker-env/bin/pip
sed -i 's:/usr/share/:/usr/data/:g' /usr/data/moonraker-env/bin/pip3

cp /usr/data/moonraker-env/bin/python3 /usr/data/moonraker-env/bin/python3.mips
cp /usr/bin/python3.8 /usr/data/moonraker-env/bin/python3

/usr/data/moonraker-env/bin/pip3 install --upgrade pip
/usr/data/moonraker-env/bin/pip3 --no-cache-dir install pyserial-asyncio==0.6
/usr/data/moonraker-env/bin/pip3 --no-cache-dir install dbus-fast==2.24.4
/usr/data/moonraker-env/bin/pip3 --no-cache-dir install apprise==1.8.0 --no-deps --upgrade
/usr/data/moonraker-env/bin/pip3 --no-cache-dir install tornado==6.4.1 --no-deps --upgrade

pushd /usr/data > /dev/null

mv /usr/data/moonraker-env/bin/python3.mips /usr/data/moonraker-env/bin/python3

tar -zcf /tmp/moonraker-env.tar.gz moonraker-env || exit $?
popd > /dev/null
