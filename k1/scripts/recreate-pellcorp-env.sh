#!/bin/sh

# THIS MUST RUN ON THE K1
if [ "$(dirname $(readlink -f $0))" != "/usr/data/pellcorp/k1/scripts" ]; then
  >&2 echo "ERROR: This git repo must be cloned to /usr/data/pellcorp"
  exit 1
fi

[ -f /usr/data/pellcorp-env.tar.gz ] && rm /usr/data/pellcorp-env.tar.gz
python3 -m virtualenv --no-setuptools --no-wheel --no-pip /usr/data/pellcorp-env || exit $?
pip3 install configupdater==3.2 --target /usr/data/pellcorp-env/lib/python3.8/site-packages/ || exit $?
cd /usr/data/ || exit $?
tar -zcf pellcorp-env.tar.gz pellcorp-env/ || exit $?
rm -rf pellcorp-env/
