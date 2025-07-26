#!/bin/sh

unset LD_LIBRARY_PATH
unset LD_PRELOAD

LOADER=ld.so.1
GLIBC=2.27

# for k1 the installed curl does not do ssl, so we replace it first
# and we can then make use of it going forward
cp /usr/data/pellcorp/k1/tools/curl /usr/bin/curl

mode=$1
if [ ! -f /opt/bin/opkg ]; then
  mode=reinstall
fi

if [ "$mode" = "reinstall" ]; then
  rm -rf /opt
  rm -rf /usr/data/opt
fi

mkdir -p /usr/data/opt
ln -nsf /usr/data/opt /opt

for folder in bin etc lib/opkg tmp var/lock; do
  mkdir -p /usr/data/opt/$folder
done

primary_host="entware.diversion.ch"
secondary_host="bin.entware.net"

download_files() {
  local url="$1"
  local output_file="$2"
  curl -L "$url" -o "$output_file"
  return $?
}

if [ "$mode" != "update" ]; then
  if download_files "http://$primary_host/mipselsf-k3.4/installer/opkg" "/opt/bin/opkg"; then
    download_files "http://$primary_host/mipselsf-k3.4/installer/opkg.conf" "/opt/etc/opkg.conf"
    # the host is hardcoded to bin.entware.net
    sed -i "s/bin.entware.net/$primary_host/g" "/opt/etc/opkg.conf"
  else
    echo -e "INFO: : Unable to download from $primary_host repo. Attempting to download from $secondary_host repo..."
    if download_files "http://$secondary_host/mipselsf-k3.4/installer/opkg" "/opt/bin/opkg"; then
      download_files "http://$secondary_host/mipselsf-k3.4/installer/opkg.conf" "/opt/etc/opkg.conf"
    else
      echo "INFO: : Failed to download from openK1 repo..."
      exit 1
    fi
  fi
fi

chmod 755 /opt/bin/opkg
chmod 777 /opt/tmp

if [ "$mode" != "update" ]; then
  /opt/bin/opkg update
  /opt/bin/opkg install entware-opt
fi

for file in passwd group shells shadow gshadow; do
  if [ -f /etc/$file ]; then
    ln -sf /etc/$file /opt/etc/$file
  else
    [ -f /opt/etc/$file.1 ] && cp /opt/etc/$file.1 /opt/etc/$file
  fi
done

[ -f /etc/localtime ] && ln -sf /etc/localtime /opt/etc/localtime

echo 'export PATH="$PATH:/opt/bin:/opt/sbin"' > /etc/profile.d/entware.sh

# this is required so that any services installed by opkg get started
cp /usr/data/pellcorp/k1/services/S50unslung /etc/init.d/

if [ ! -f /opt/libexec/sftp-server ]; then
  # by default dropbear does not come with sftp support, so this enables it
  /opt/bin/opkg install openssh-sftp-server || exit $?
fi
ln -sf /opt/libexec/sftp-server /usr/libexec/sftp-server

if [ ! -f /opt/bin/bash ]; then
  /opt/bin/opkg install bash
fi
ln -sf /opt/bin/bash /bin/
