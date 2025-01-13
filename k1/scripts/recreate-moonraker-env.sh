#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"
K1_DIR="$(dirname $CURRENT_DIR)"

# not sure this is necessary but I want to use the same version of python to update the env
if [ ! /usr/bin/python3.8 ]; then
    echo "Need python 3.8"
    exit 1
fi
/usr/bin/python3.8 -m ensurepip

wget https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz -O /tmp/moonraker.tar.gz
tar -zxvf /tmp/moonraker.tar.gz -C /tmp moonraker/moonraker-env
rm /tmp/moonraker.tar.gz

# the env was originally for /usr/share/moonraker-env
#!/usr/data/moonraker/moonraker-env/bin/python
sed -i 's:/usr/data/moonraker/:/usr/data/:g' /tmp/moonraker/moonraker-env/bin/activate
sed -i 's:/usr/data/moonraker/:/usr/data/:g' /tmp/moonraker/moonraker-env/bin/pip
sed -i 's:/usr/data/moonraker/:/usr/data/:g' /tmp/moonraker/moonraker-env/bin/pip3

# and we are never going to need these
rm /tmp/moonraker/moonraker-env/bin/activate.csh
rm /tmp/moonraker/moonraker-env/bin/activate.fish

pushd /tmp/moonraker > /dev/null
tar -zcf $K1_DIR/moonraker-env.tar.gz moonraker-env || exit $?
popd > /dev/null
rm -rf /tmp/moonraker
