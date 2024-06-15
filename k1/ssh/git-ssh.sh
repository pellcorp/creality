#!/bin/sh

dbclient -y -i ~/.ssh/$GIT_SSH_IDENTITY-identity $*
