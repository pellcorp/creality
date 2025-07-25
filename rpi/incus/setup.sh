#!/bin/bash

apt-get update
apt-get install -y openssh-server sudo git plymouth
systemctl enable ssh 2> /dev/null
echo "%sudo  ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopasswd > /dev/null
sudo useradd -m -s /bin/bash me
sudo usermod -a -G sudo me
echo "me:raspberry" | sudo chpasswd
mkdir -p /home/me/.ssh
cat /root/id_rsa.pub >> /home/me/.ssh/authorized_keys
sudo chown -R me: /home/me/.ssh
