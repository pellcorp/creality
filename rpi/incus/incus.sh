#!/bin/bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
RPI_DIR=$(dirname $CURRENT_DIR)
ROOT_DIR=$(dirname $RPI_DIR)

incus delete klipper --force 2> /dev/null

incus network set incusbr0 ipv6.firewall false
incus network set incusbr0 ipv4.firewall false
incus network set incusbr0 ipv4.dhcp true

sudo firewall-cmd --permanent --zone=trusted --add-interface=incusbr0
sudo firewall-cmd --reload

# this is required so that ping and other things work and needs to be after firewall-cmd
sudo iptables -P FORWARD ACCEPT

default_user=me
if [ "$1" = "jammy" ]; then
    incus init images:ubuntu/jammy/cloud klipper --vm --config=cloud-init.user-data="$(cat $CURRENT_DIR/cloud-config.yml)" || exit $?
elif [ "$1" = "noble" ]; then
    incus init images:ubuntu/noble/cloud klipper --vm --config=cloud-init.user-data="$(cat $CURRENT_DIR/cloud-config.yml)" || exit $?
elif [ "$1" = "11" ]; then
    incus init images:debian/11/cloud klipper --vm --config=cloud-init.user-data="$(cat $CURRENT_DIR/cloud-config.yml)" || exit $?
elif [ "$1" = "12" ]; then
    incus init images:debian/12/cloud klipper --vm --config=cloud-init.user-data="$(cat $CURRENT_DIR/cloud-config.yml)" || exit $?
else
    incus init images:debian/13/cloud klipper --vm --config=cloud-init.user-data="$(cat $CURRENT_DIR/cloud-config.yml)" || exit $?
fi
incus config set klipper security.secureboot false || exit $?
incus config set klipper limits.cpu 4 || exit $?
incus config set klipper limits.memory 2048MB || exit $?
incus config device override klipper root size=16GB || exit $?
incus config device add klipper pellcorp disk source=$ROOT_DIR path=/home/me/pellcorp || exit $?
incus start klipper

echo -n "Waiting for klipper to start ."
while true; do
  incus exec klipper -- id -u $default_user > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    break
  else
    echo -n "."
    sleep 1
  fi
done

incus file push $HOME/.ssh/id_rsa.pub "klipper/root/id_rsa.pub"

# seems like running this again before setup might fix some issues no idea why, perhaps this is a fedora thing
sudo iptables -P FORWARD ACCEPT

incus exec klipper -- /home/me/pellcorp/rpi/incus/setup.sh

IP_ADDRESS=$(incus info klipper | grep inet | head -1 | awk -F ':' '{print $2}' | sed 's:/24 (global)::g' | tr -d '[:space:]')
ssh-keygen -f "$HOME/.ssh/known_hosts" -R $IP_ADDRESS > /dev/null 2>&1
ssh-keyscan -t rsa "$IP_ADDRESS" >> "$HOME/.ssh/known_hosts" 2> /dev/null

# flip it back yo
incus network set incusbr0 ipv4.dhcp false

ssh me@$IP_ADDRESS
