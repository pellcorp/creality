#!/bin/sh

if [ ! -f /usr/data/pellcorp.done ]; then
    echo "ERROR: Missing installation"
    exit 1
fi

cd /usr/data/pellcorp
git fetch

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "You are on branch $BRANCH"

PELLCORP_GIT_SHA=$(cat /usr/data/pellcorp.done | grep "installed_sha" | awk -F '=' '{print $2}')
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
