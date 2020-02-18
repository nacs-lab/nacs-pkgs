#!/bin/bash

mkinitcpio -p linux$1
mkimage -A arm -O linux -T ramdisk -C gzip -d /boot/ramdisk.image.gz \
        /boot/uramdisk.image.gz
rm /boot/ramdisk.image.gz
