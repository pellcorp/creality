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

primary_URL="https://bin.entware.net/mipselsf-k3.4/installer"
secondary_URL="http://www.openk1.org/static/entware/mipselsf-k3.4/installer"

download_files() {
  local url="$1"
  local output_file="$2"
  curl -L "$url" -o "$output_file"
  return $?
}

if [ "$mode" = "reinstall" ]; then
  if download_files "$primary_URL/opkg" "/opt/bin/opkg"; then
    download_files "$primary_URL/opkg.conf" "/opt/etc/opkg.conf"
  else
    echo -e "Info: Unable to download from Entware repo. Attempting to download from openK1 repo..."
    if download_files "$secondary_URL/opkg" "/opt/bin/opkg"; then
      download_files "$secondary_URL/opkg.conf" "/opt/etc/opkg.conf"
    else
      echo "Info: Failed to download from openK1 repo..."
      exit 1
    fi
  fi
fi
chmod 755 /opt/bin/opkg
chmod 777 /opt/tmp

/opt/bin/opkg update
/opt/bin/opkg install entware-opt

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

# by default dropbear does not come with sftp support, so this enables it
/opt/bin/opkg install openssh-sftp-server || exit $?
ln -sf /opt/libexec/sftp-server /usr/libexec/sftp-server

/opt/bin/opkg install bash
ln -sf /opt/bin/bash /bin/
