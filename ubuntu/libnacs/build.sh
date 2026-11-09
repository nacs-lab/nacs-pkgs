#!/bin/bash

DEB_REL=0ubuntu1

enable_simd=On
if [[ $UBUNTU_VER = 18.04 ]]; then
    enable_simd=Off
fi

MAKEFLAGS="-j$(nproc)"

patch_file="$(cd "$(dirname "$0")" && pwd)/llvm-iterator.patch"
if git -C libnacs apply --check "$patch_file"; then
    git -C libnacs apply "$patch_file"
elif ! git -C libnacs apply --reverse --check "$patch_file"; then
    echo "Unable to apply LLVM iterator compatibility patch"
    exit 1
fi

cd libnacs
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
      -DENABLE_SIMD=${enable_simd} -DENABLE_LLVM=On -DENABLE_TESTING=Off \
      -DCPACK_DEBIAN_PACKAGE_RELEASE=$DEB_REL \
      -DLLVM_DIR=/usr/lib/llvm-${LLVM_VER}/cmake

cd build
make
cpack ..
