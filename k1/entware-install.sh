#!/bin/sh

unset LD_LIBRARY_PATH
unset LD_PRELOAD

LOADER=ld.so.1
GLIBC=2.27

rm -rf /opt
rm -rf /usr/data/opt

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
  /usr/data/pellcorp/k1/tools/curl -L "$url" -o "$output_file"
  return $?
}

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

echo 'export PATH="/opt/bin:/opt/sbin:$PATH"' > /etc/profile.d/entware.sh

# this is required so that any services installed by opkg get started
echo '#!/bin/sh\n/opt/etc/init.d/rc.unslung "$1"' > /etc/init.d/S50unslung
chmod 755 /etc/init.d/S50unslung

# by default openbear does not come with sftp support, so this enables it
/opt/bin/opkg install openssh-sftp-server || exit $?
ln -sf /opt/libexec/sftp-server /usr/libexec/sftp-server
