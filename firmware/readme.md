# Custom Firmware

I have been working on a script to create custom firmware, with the idea of potentially providing 
firmware for the k1 that has my klipper repo, no creality gcode, all preconfigured.

** I WILL NOT BE HELD RESPONSIBLE IF YOU BRICK YOUR PRINTER - CREATING AND INSTALLING CUSTOM FIRMWARE IS RISKY **

## Prerequisites

You will need a linux machine with the following commands available, something like ubuntu or arch is fine:

- p7zip (7z command)
- wget
- unsquashfs
- mksquashfs

The packages on ubuntu can be installed like so:

```
sudo apt-get install p7zip squashfs-tools wget
```

Don't try and create this on windows or MacOs, you could do it on a ubuntu vm no problem

## Creating

Then you can create a new firmware file, currently without any customations just to test things work with:

```
export K1_FIRMWARE_PASSWORD='the password from a certain discord'
./create.sh
```

**NOTE:** You will be required to enter your `sudo` password

The resulting img file will be located at `/tmp/1.3.3.8-pellcorp/CR4CU220812S11_ota_img_V6.1.3.3.8.img`

## Testing

It's very important to test this in the safest way possible, luckily creality has provided a way to test
a new firmware image from the cli rather than relying on the display server

```
/etc/ota_bin/local_ota_update.sh /tmp/udisk/sda1/CR4CU220812S11_ota_img_V6.1.3.3.8.img
```

## Thanks

Thanks for destinal from discord for providing information about testing the image and also for providing 
the password creality uses for generating the image.

https://www.reddit.com/r/crealityk1/comments/15d3b8k/reverting_to_stock_firmware_on_the_k1_or_k1_max/  


I also have used a couple of his init.d scripts which I got from 
https://openk1.org/static/k1/packages/crealityos-root-init-scripts.tar.gz
