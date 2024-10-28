#!/bin/sh

cd /usr/data/pellcorp
git fetch

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "You are on branch $BRANCH"

CURRENT_REVISION=$(git rev-parse HEAD)
LATEST_REVISION=$(git rev-parse $(git rev-parse --abbrev-ref HEAD)@{upstream})
if [ "$CURRENT_REVISION" != "$LATEST_REVISION" ]; then
  echo "There are updates available:"
  git --no-pager log --no-color ${CURRENT_REVISION}..${LATEST_REVISION}
else
  echo "There are no updates available"
fi
