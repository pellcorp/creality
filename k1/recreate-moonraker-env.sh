#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"

# FIXME - figure out how to recreate the moonraker-env locally from scratch
# as the one from Guilouz seems to have additional packages that should not be needed
# but so far I have failed to do that :-(

# if [ ! /usr/bin/python3.8 ] || [ ! /usr/bin/virtualenv ]; then
#     echo "Need python 3.8 and virtual to create virtual env for k1"
#     exit 1
# fi

# wget https://raw.githubusercontent.com/pellcorp/moonraker/master/scripts/moonraker-requirements.txt -O /tmp/moonraker-requirements.txt 
# virtualenv -p /usr/bin/python3.8 /tmp/moonraker-env
# /tmp/moonraker-env/bin/pip install -r /tmp/moonraker-requirements.txt || exit $?
# # no binaries here
# find /tmp/moonraker-env/ -name "*.so" -exec rm {} \;
# rm /tmp/moonraker-env/bin/python
# pushd /tmp > /dev/null
# tar -zcf $CURRENT_DIR/moonraker-env.tar.gz moonraker-env || exit $?
# rm -rf /tmp/moonraker-env
# rm /tmp/moonraker-requirements.txt

wget https://github.com/Guilouz/Creality-Helper-Script/raw/main/files/moonraker/moonraker.tar.gz -O /tmp/moonraker.tar.gz
tar -zxvf /tmp/moonraker.tar.gz -C /tmp moonraker/moonraker-env
rm /tmp/moonraker.tar.gz

pip install --target /tmp/moonraker/moonraker-env/lib/python3.8/site-packages/ pyserial-asyncio==0.6
pip install --target /tmp/moonraker/moonraker-env/lib/python3.8/site-packages/ apprise==1.7.1 --no-deps --upgrade

pushd /tmp/moonraker > /dev/null
tar -zcf $CURRENT_DIR/moonraker-env.tar.gz moonraker-env || exit $?
popd > /dev/null
rm -rf /tmp/moonraker
