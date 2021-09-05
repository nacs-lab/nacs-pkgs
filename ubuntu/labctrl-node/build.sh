#!/bin/bash

DEB_REL="0ubuntu1~node${NODE_VER}"

MAKEFLAGS="-j$(nproc)"

cd labctrl-node
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
      -DCPACK_DEBIAN_PACKAGE_RELEASE=$DEB_REL

cd build
make
make deploy
cpack ..
