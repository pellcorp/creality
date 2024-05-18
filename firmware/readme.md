# Custom Firmware

I have been working on a script to create custom firmware, with the idea of potentially providing 
firmware for the k1 that has my klipper repo, no creality gcode, all preconfigured.

## Creating

The create.sh script can be used, you will need to copy the firmware password to the file `~/.k1/firmware.passwd`.

Then you can create a new firmware file, currently without any customations just to test things work with:

```
./create.sh
```

**NOTE:** You will be required to enter your `sudo` password

The resulting img file will be located at `/tmp/1.3.3.8-pellcorp/CR4CU220812S11_ota_img_V5.1.3.3.8.img`

## Testing

It's very important to test this in the safest way possible, luckily creality has provided a way to test
a new firmware image from the cli rather than relying on the display server

```
/etc/ota_bin/local_ota_update.sh /tmp/udisk/sda1/CR4CU220812S11_ota_img_V5.1.3.3.8.img
```

## Thanks

Thanks for destinal from discord for providing information about testing the image and also for providing 
the password creality uses for generating the image.

https://www.reddit.com/r/crealityk1/comments/15d3b8k/reverting_to_stock_firmware_on_the_k1_or_k1_max/  


I also have used a couple of his init.d scripts which I got from 
https://openk1.org/static/k1/packages/crealityos-root-init-scripts.tar.gz