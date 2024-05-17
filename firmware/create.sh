#!/bin/bash

function update_rootfs() {
    pushd /tmp/${version}-pellcorp/ > /dev/null
    sudo unsquashfs orig_rootfs.squashfs 
    #echo "I was here" > /tmp/${version}-pellcorp/squashfs-root/etc/me
    sudo mksquashfs squashfs-root rootfs.squashfs || exit $?
    sudo rm -rf squashfs-root
}

# if you look hard enough you can find the password on the interwebs in a certain discord
password="$(cat ~/.k1/firmware.passwd)"
version=1.3.3.8

if [ -z "$password" ]; then
    echo "Creality K1 firmware password missing - should be in ~/.k1/firmware.passwd!!!"
    exit 1
fi

download=$(wget -q https://www.creality.com/pages/download-k1-flagship -O- | grep -o  "\"\(.*\)V${version}.img\"" | head -1 | tr -d '"')
filename=$(basename $download)
directory=$(echo $filename | sed 's/\.img//g')
sub_directory="ota_v${version}"

if [ ! -f /tmp/$filename ]; then
    echo "Downloading $download -> /tmp/$filename ..."
    wget "$download" -O /tmp/$filename
fi

if [ -d /tmp/$directory ]; then
    rm -rf /tmp/$directory
fi

7z x /tmp/$filename -p"$password" -o/tmp

if [ -d /tmp/${version}-pellcorp ]; then
    sudo rm -rf /tmp/${version}-pellcorp
fi
mkdir -p /tmp/${version}-pellcorp/$directory/$sub_directory

cat /tmp/$directory/$sub_directory/rootfs.squashfs.* > /tmp/${version}-pellcorp/orig_rootfs.squashfs
orig_rootfs_md5=$(md5sum /tmp/${version}-pellcorp/orig_rootfs.squashfs | awk '{print $1}')
orig_rootfs_size=$(stat -c%s /tmp/${version}-pellcorp/orig_rootfs.squashfs)

# do the changes here
update_rootfs || exit $?

rootfs_md5=$(md5sum /tmp/${version}-pellcorp/rootfs.squashfs | awk '{print $1}')
rootfs_size=$(stat -c%s  /tmp/${version}-pellcorp/rootfs.squashfs)

echo "current_version=$version" > /tmp/${version}-pellcorp/$directory/ota_config.in
echo "" > /tmp/${version}-pellcorp/$directory/$sub_directory/ota_v${version}.ok

cp /tmp/$directory/$sub_directory/ota_update.in /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$directory/$sub_directory/ota_md5_xImage* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$directory/$sub_directory/ota_md5_zero.bin* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$directory/$sub_directory/zero.bin.* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$directory/$sub_directory/xImage.* /tmp/${version}-pellcorp/$directory/$sub_directory/

pushd /tmp/${version}-pellcorp/$directory/$sub_directory > /dev/null
split -d -b 1048576 -a 4 /tmp/${version}-pellcorp/rootfs.squashfs rootfs.squashfs.
popd > /dev/null
#rm /tmp/${version}-pellcorp/rootfs.squashfs

for i in $(ls /tmp/${version}-pellcorp/$directory/$sub_directory/rootfs.squashfs.*); do
    file=$(basename $i)
    id=$(uuidgen | tr -d '-')
    mv "/tmp/${version}-pellcorp/$directory/$sub_directory/$file" "/tmp/${version}-pellcorp/$directory/$sub_directory/${file}.${id}"
    echo "$id" >> "/tmp/${version}-pellcorp/$directory/$sub_directory/ota_md5_rootfs.squashfs.${rootfs_md5}"
done

sed -i "s/img_md5=$orig_rootfs_md5/img_md5=$rootfs_md5/g" /tmp/${version}-pellcorp/$directory/$sub_directory/ota_update.in
sed -i "s/img_size=$orig_rootfs_size/img_size=$rootfs_size/g" /tmp/${version}-pellcorp/$directory/$sub_directory/ota_update.in

# TODO recreate 7z img file from 
pushd /tmp/${version}-pellcorp/ > /dev/null

base_filename=$(basename $filename .img)
7z a $base_filename.7z -p"$password" $directory
mv $base_filename.7z $base_filename.7z.img

popd > /dev/null
