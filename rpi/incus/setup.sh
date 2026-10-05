#!/bin/bash

echo "%sudo  ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopasswd > /dev/null

mkdir -p /home/me/.ssh
cat /root/id_rsa.pub >> /home/me/.ssh/authorized_keys
sudo chown -R me: /home/me/.ssh
sudo chown me: /home/me

apt-get update
apt-get install -y openssh-server sudo git plymouth make
systemctl enable ssh 2> /dev/null
