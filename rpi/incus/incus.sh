#!/bin/bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
ROOT_DIR=$(dirname $CURRENT_DIR)

incus delete klipper --force 2> /dev/null

sudo iptables -P FORWARD ACCEPT
sudo ufw allow in on incusbr0
sudo ufw route allow in on incusbr0
sudo ufw route allow out on incusbr0
incus network set incusbr0 ipv6.firewall false
incus network set incusbr0 ipv4.firewall false

if [ "$1" = "11" ]; then
    incus init images:debian/11/cloud klipper --vm || exit $?
else
    incus init images:debian/12/cloud klipper --vm || exit $?
fi
incus config set klipper security.secureboot false || exit $?
incus config set klipper limits.cpu 4 || exit $?
incus config set klipper limits.memory 2048MB || exit $?
incus config device override klipper root size=16GB || exit $?
incus config device add klipper projects disk source=$ROOT_DIR path=/opt/projects/ || exit $?
incus start klipper

echo -n "Waiting for klipper to start ."
while true; do
  incus exec klipper -- id -u debian > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    break
  else
    echo -n "."
    sleep 1
  fi
done

incus file push $HOME/.ssh/id_rsa.pub "klipper/root/id_rsa.pub"
incus exec klipper -- /opt/projects/incus/setup.sh

IP_ADDRESS=$(incus info klipper | grep inet | head -1 | awk -F ':' '{print $2}' | sed 's:/24 (global)::g' | tr -d '[:space:]')
#IP_ADDRESS=$(incus exec klipper -- bash -c "ip route | grep 'default' | awk '{print \$9}' | tail -1" 2> /dev/null)
ssh-keygen -f "$HOME/.ssh/known_hosts" -R $IP_ADDRESS > /dev/null 2>&1
ssh-keyscan -t rsa "$IP_ADDRESS" >> "$HOME/.ssh/known_hosts" 2> /dev/null

ssh me@$IP_ADDRESS
