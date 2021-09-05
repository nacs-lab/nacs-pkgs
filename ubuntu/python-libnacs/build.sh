#!/bin/bash

DEB_REL=0ubuntu1

MAKEFLAGS="-j$(nproc)"

cd python-libnacs
cmake -B build -DCMAKE_BUILD_TYPE=Release -DPYTHON_EXECUTABLE=/usr/bin/python3 \
      -DCPACK_DEBIAN_PACKAGE_RELEASE=$DEB_REL

cd build
make
cpack ..
