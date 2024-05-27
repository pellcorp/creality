#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"

wget https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz -O /tmp/moonraker.tar.gz
tar -zxvf /tmp/moonraker.tar.gz -C /tmp moonraker/moonraker-env
rm /tmp/moonraker.tar.gz

# not sure this is necessary but I want to use the same version of python to update the env
if [ ! /usr/bin/python3.8 ]; then
    echo "Need python 3.8"
    exit 1
fi
/usr/bin/python3.8 -m ensurepip

/usr/bin/python3.8 -m pip install --target /tmp/moonraker/moonraker-env/lib/python3.8/site-packages/ pyserial-asyncio==0.6
/usr/bin/python3.8 -m pip install --target /tmp/moonraker/moonraker-env/lib/python3.8/site-packages/ apprise==1.7.1 --no-deps --upgrade

# the env was originally for /usr/share/moonraker-env
sed -i 's:/usr/share/:/usr/data/:g' /tmp/moonraker/moonraker-env/bin/activate

# and we are never going to need these
rm /tmp/moonraker/moonraker-env/bin/activate.csh
rm /tmp/moonraker/moonraker-env/bin/activate.fish

pushd /tmp/moonraker > /dev/null
tar -zcf $CURRENT_DIR/moonraker-env.tar.gz moonraker-env || exit $?
popd > /dev/null
rm -rf /tmp/moonraker
