#!/bin/sh

INSTALLED_SHA=$(grep "installed_sha" /usr/data/pellcorp.done 2> /dev/null | awk -F '=' '{print $2}')
cd /usr/data/pellcorp || exit 1
GIT_SHA=$(git rev-parse HEAD)
if [ -z "$INSTALLED_SHA" ] || [ "$INSTALLED_SHA" = "$GIT_SHA" ]; then
    exit 0
fi

# send a message to the fluidd / mainsail console, ignored while klipper is restarting
console() {
    msg=$(echo "$1" | tr -d "\"'")
    curl -s -m 5 -X POST http://localhost:7125/printer/gcode/script --data-urlencode "script=RESPOND MSG=\"$msg\"" > /dev/null 2>&1
}

# give moonraker time to finish the update
sleep 5
console "Simple AF update started"
/usr/data/pellcorp/k1/installer.sh --update 2>&1 | while IFS= read -r line; do
    case "$line" in
        INFO:*|WARNING:*|ERROR:*|FATAL:*) console "$line" ;;
    esac
done

# wait for klipper to come back after the installer restarts it
i=0
while [ $i -lt 24 ]; do
    curl -s -m 5 http://localhost:7125/printer/info | grep -q '"state": *"ready"' && break
    sleep 5
    i=$((i+1))
done

INSTALLED_SHA=$(grep "installed_sha" /usr/data/pellcorp.done 2> /dev/null | awk -F '=' '{print $2}')
if [ "$INSTALLED_SHA" = "$GIT_SHA" ]; then
    console "Simple AF update complete"
else
    console "ERROR: Simple AF update failed, check the installer log"
fi
