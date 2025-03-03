#!/bin/sh

if [ -f /usr/data/pellcorp/k1/ssh/$GIT_SSH_IDENTITY-identity ]; then
    dbclient -y -i /usr/data/pellcorp/k1/ssh/$GIT_SSH_IDENTITY-identity $* 2> /dev/null
elif [ -f /root/.ssh/$GIT_SSH_IDENTITY-identity ]; then
    dbclient -y -i /root/.ssh/$GIT_SSH_IDENTITY-identity $* 2> /dev/null
else
    echo "ERROR: No $GIT_SSH_IDENTITY-identity identity"
    exit 1
fi
