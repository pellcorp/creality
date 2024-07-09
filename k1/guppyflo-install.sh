#!/bin/sh

function display_guppyflo_post_install_instruction() {
    TS_AUTH_URL=$(grep -o -m 1 "https://login.tailscale.com/.*" /usr/data/printer_data/logs/guppyflo.log 2>/dev/null)
    for i in $(seq 1 10); do
	    if [ -n "$TS_AUTH_URL" ]; then
            printf "1. Open following tailscale authentication URL to add this printer to your tailnet:\n"
            printf "$TS_AUTH_URL\n\n"
            printf "2. Enable Tailscale MagicDNS:\n"
            printf "https://login.tailscale.com/admin/dns\n\n"
            printf "3. Download the tailscale client, sign-in, and connect your client to your tailnet:\n"
            printf "https://tailscale.com/download\n\n"
            printf "4. Remote access UI at:\n"
            printf "http://guppyflo\n\n"
            break;
	    fi
      sleep 2
      TS_AUTH_URL=$(grep -o -m 1 "https://login.tailscale.com/.*" /usr/data/printer_data/logs/guppyflo.log 2>/dev/null)
    done
}

function install_guppyflo() {
    echo ""
    echo "Installing guppyflo ..."

    if [ -d /usr/data/guppyflo ]; then
        if [ -f /etc/init.d/S99guppyflo ]; then
            /etc/init.d/S99guppyflo stop > /dev/null 2>&1
        fi
        killall -q guppyflo
        rm -rf /usr/data/guppyflo
    fi

    if [ -f /usr/data/printer_data/logs/guppyflo.log ]; then
      rm /usr/data/printer_data/logs/guppyflo.log
    fi

    curl -L https://github.com/ballaswag/guppyflo/releases/download/nightly/guppyflo_mipsle.zip -o /tmp/guppyflo.zip || exit $?
    #curl -L https://github.com/ballaswag/guppyflo/releases/latest/download/guppyflo_mipsle.zip -o /tmp/guppyflo.zip || exit $?
    mkdir -p /usr/data/guppyflo
    unzip /tmp/guppyflo.zip -d /usr/data/guppyflo guppyflo || exit $?
    rm /tmp/guppyflo.zip || exit $?
    cp /usr/data/pellcorp/k1/services/S99guppyflo /etc/init.d/ || exit $?
    cp /usr/data/pellcorp/k1/proxies.json /usr/data/guppyflo/ || exit $?

    echo ""
    echo "Starting guppyflo ..."
    sync

    /etc/init.d/S99guppyflo start
    display_guppyflo_post_install_instruction
}

install_guppyflo
