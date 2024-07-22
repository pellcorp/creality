#!/bin/sh

dbclient -y -i /usr/data/pellcorp/k1/ssh/$GIT_SSH_IDENTITY-identity $* 2> /dev/null
