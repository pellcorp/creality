#!/bin/sh

BASEDIR=/home/pi
if grep -Fqs "ID=buildroot" /etc/os-release; then
    BASEDIR=/usr/data
fi

if [ ! -f $BASEDIR/pellcorp.done ]; then
    echo "ERROR: Missing installation"
    exit 1
fi

cd $BASEDIR/pellcorp
git fetch

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "You are on branch $BRANCH"

PELLCORP_GIT_SHA=$(cat $BASEDIR/pellcorp.done | grep "installed_sha" | awk -F '=' '{print $2}')
if [ -n "$PELLCORP_GIT_SHA" ]; then
    CURRENT_REVISION=$PELLCORP_GIT_SHA
else
    CURRENT_REVISION=$(git rev-parse HEAD)
fi

LATEST_REVISION=$(git rev-parse $(git rev-parse --abbrev-ref HEAD)@{upstream})
if [ "$CURRENT_REVISION" != "$LATEST_REVISION" ]; then
  echo "There are updates available:"
  git --no-pager log --no-color ${CURRENT_REVISION}..${LATEST_REVISION}
else
  echo "There are no updates available"
fi
