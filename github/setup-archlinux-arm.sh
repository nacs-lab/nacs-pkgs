#!/bin/bash

pacman -S --noconfirm arch-arm-git armv7l-linux-gnueabihf-gcc
mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
pacman-armv7 -Sy --noconfirm base-devel
