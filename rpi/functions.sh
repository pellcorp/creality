#!/bin/bash

# stolen from https://github.com/lavabit/robox/
function retry() {
  local COUNT=1
  local DELAY=0
  local RESULT=0
  while [[ "${COUNT}" -le 10 ]]; do
    [[ "${RESULT}" -ne 0 ]] && {
      [ "`which tput 2> /dev/null`" != "" ] && [ -n "$TERM" ] && tput setaf 1
      echo -e "\n${*} failed... retrying ${COUNT} of 10.\n" >&2
      [ "`which tput 2> /dev/null`" != "" ] && [ -n "$TERM" ] && tput sgr0
    }
    "${@}" && { RESULT=0 && break; } || RESULT="${?}"
    COUNT="$((COUNT + 1))"

    # Increase the delay with each iteration.
    DELAY="$((DELAY + 10))"
    sleep $DELAY
  done

  [[ "${COUNT}" -gt 10 ]] && {
    [ "`which tput 2> /dev/null`" != "" ] && [ -n "$TERM" ] && tput setaf 1
    echo -e "\nThe command failed 10 times.\n" >&2
    [ "`which tput 2> /dev/null`" != "" ] && [ -n "$TERM" ] && tput sgr0
  }

  return "${RESULT}"
}

function error() {
  if [ $? -ne 0 ]; then
    printf "\n\napt failed...\n\n";
    exit 1
  fi
}

debian_release=$(lsb_release -rs 2> /dev/null | tr -d '.')
# hackery for ubuntu
if [ $debian_release -ge 2404 ]; then
  debian_release=13
elif [ $debian_release -ge 2204 ]; then
  debian_release=12
elif [ $debian_release -ge 2004 ]; then
  debian_release=11
fi
