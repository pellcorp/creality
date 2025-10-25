#!/bin/sh

while true; do ping -c1 -W1 8.8.8.8 >/dev/null; sleep 30; done
