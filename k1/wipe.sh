#!/bin/bash

if [ "$1" = "all" ] || [ "$1" = "partial" ]; then
    echo "$1" | nc -U /var/run/wipe.sock
else
    echo "Invalid argument"
fi

