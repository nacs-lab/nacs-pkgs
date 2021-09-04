#!/bin/bash

pacman -S --noconfirm arch-arm-git armv7l-linux-gnueabihf-gcc
mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
for ((i = 0; i < 10; i++)); do
    # Retry a few times since the ArchLinux ARM mirrors seem to be unreliable at times.
    pacman-armv7 -Sy --noconfirm base-devel && break
done
