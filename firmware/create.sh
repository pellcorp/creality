#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"

commands="7z unsquashfs mksquashfs mkpasswd"
for command in $commands; do
    command -v "$command" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Command $command not found"
        exit 1
    fi
done

BOARD_SHORT_NAME=CR4CU220812S11
DOWNLOAD_PAGE=download-k1-flagship
CREALITY_VERSION=1.3.3.8

# thanks to Neon for showing me how to derive the password
FIRMWARE_PASSWORD=$(mkpasswd -m md5 "${BOARD_SHORT_NAME}C3_7e_bz" -S cxswfile)

version="6.${CREALITY_VERSION}"

function write_ota_info() {
    echo "ota_version=${version}" > /tmp/${version}-pellcorp/ota_info
    echo "ota_board_name=${board_name}" >> /tmp/${version}-pellcorp/ota_info
    echo "ota_compile_time=$(date '+%Y %m.%d %H:%M:%S')" >> /tmp/${version}-pellcorp/ota_info
    echo "ota_site=http://192.168.43.52/ota/board_test" >> /tmp/${version}-pellcorp/ota_info
    sudo cp /tmp/${version}-pellcorp/ota_info /tmp/${version}-pellcorp/squashfs-root/etc/
}

function customise_rootfs() {
    write_ota_info
    sudo cp $CURRENT_DIR/etc/init.d/* /tmp/${version}-pellcorp/squashfs-root/etc/init.d/
}

function update_rootfs() {
    pushd /tmp/${version}-pellcorp/ > /dev/null
    sudo unsquashfs orig_rootfs.squashfs 
    customise_rootfs
    sudo mksquashfs squashfs-root rootfs.squashfs || exit $?
    sudo rm -rf squashfs-root
    sudo chown $USER rootfs.squashfs 
}

download=$(wget -q https://www.creality.com/pages/${DOWNLOAD_PAGE} -O- | grep -o  "\"\(.*\)V${CREALITY_VERSION}.img\"" | head -1 | tr -d '"')
old_image_name=$(basename $download)
board_name=$(echo "$old_image_name" | grep -o "\(CR.*\)ota" | sed 's/_ota//g')
old_directory="${board_name}_ota_img_V${CREALITY_VERSION}"
old_sub_directory="ota_v${CREALITY_VERSION}"
directory="${board_name}_ota_img_V${version}"
sub_directory="ota_v${version}"
image_name="${board_name}_ota_img_V${version}".img

if [ ! -f /tmp/$old_image_name ]; then
    echo "Downloading $download -> /tmp/$old_image_name ..."
    wget "$download" -O /tmp/$old_image_name
fi

if [ -d /tmp/$old_directory ]; then
    rm -rf /tmp/$old_directory
fi

7z x /tmp/$old_image_name -p"$FIRMWARE_PASSWORD" -o/tmp

if [ -d /tmp/${version}-pellcorp ]; then
    sudo rm -rf /tmp/${version}-pellcorp
fi
mkdir -p /tmp/${version}-pellcorp/$directory/$sub_directory

cat /tmp/$old_directory/$old_sub_directory/rootfs.squashfs.* > /tmp/${version}-pellcorp/orig_rootfs.squashfs
orig_rootfs_md5=$(md5sum /tmp/${version}-pellcorp/orig_rootfs.squashfs | awk '{print $1}')
orig_rootfs_size=$(stat -c%s /tmp/${version}-pellcorp/orig_rootfs.squashfs)

# do the changes here
update_rootfs || exit $?

rootfs_md5=$(md5sum /tmp/${version}-pellcorp/rootfs.squashfs | awk '{print $1}')
rootfs_size=$(stat -c%s /tmp/${version}-pellcorp/rootfs.squashfs)

echo "current_version=$version" > /tmp/${version}-pellcorp/$directory/ota_config.in
echo "" > /tmp/${version}-pellcorp/$directory/$sub_directory/ota_v${version}.ok

cp /tmp/$old_directory/$old_sub_directory/ota_update.in /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$old_directory/$old_sub_directory/ota_md5_xImage* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$old_directory/$old_sub_directory/ota_md5_zero.bin* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$old_directory/$old_sub_directory/zero.bin.* /tmp/${version}-pellcorp/$directory/$sub_directory/
cp /tmp/$old_directory/$old_sub_directory/xImage.* /tmp/${version}-pellcorp/$directory/$sub_directory/

pushd /tmp/${version}-pellcorp/$directory/$sub_directory > /dev/null
split -d -b 1048576 -a 4 /tmp/${version}-pellcorp/rootfs.squashfs rootfs.squashfs.
popd > /dev/null

part_md5=
for i in $(ls /tmp/${version}-pellcorp/$directory/$sub_directory/rootfs.squashfs.*); do
    file=$(basename $i)
    if [ -z "$part_md5" ]; then
        id=$rootfs_md5
    else
        id=$part_md5
    fi
    mv "/tmp/${version}-pellcorp/$directory/$sub_directory/$file" "/tmp/${version}-pellcorp/$directory/$sub_directory/${file}.${id}"
    part_md5=$(md5sum /tmp/${version}-pellcorp/$directory/$sub_directory/${file}.${id} | awk '{print $1}')
    echo "$part_md5" >> "/tmp/${version}-pellcorp/$directory/$sub_directory/ota_md5_rootfs.squashfs.${rootfs_md5}"
done

sed -i "s/ota_version=$CREALITY_VERSION/ota_version=$version/g" /tmp/${version}-pellcorp/$directory/$sub_directory/ota_update.in
sed -i "s/img_md5=$orig_rootfs_md5/img_md5=$rootfs_md5/g" /tmp/${version}-pellcorp/$directory/$sub_directory/ota_update.in
sed -i "s/img_size=$orig_rootfs_size/img_size=$rootfs_size/g" /tmp/${version}-pellcorp/$directory/$sub_directory/ota_update.in

pushd /tmp/${version}-pellcorp/ > /dev/null
7z a ${image_name}.7z -p"$K1_FIRMWARE_PASSWORD" $directory
mv ${image_name}.7z ${image_name}
popd > /dev/null
