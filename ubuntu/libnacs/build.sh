#!/bin/bash

DEB_REL=0ubuntu1

enable_simd=On
if [[ $UBUNTU_VER = 18.04 ]]; then
    enable_simd=Off
fi

MAKEFLAGS="-j$(nproc)"

cd libnacs
cmake -B build -DCMAKE_BUILD_TYPE=Release -DENABLE_SIMD=${enable_simd} \
      -DENABLE_LLVM=On -DENABLE_TESTING=Off -DCPACK_DEBIAN_PACKAGE_RELEASE=$DEB_REL

cd build
make
cpack ..
