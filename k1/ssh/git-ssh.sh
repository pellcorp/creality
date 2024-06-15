#!/bin/sh

dbclient -y -i ~/.ssh/$GIT_SSH_IDENTITY-identity $* 2> /dev/null
