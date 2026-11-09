#!/bin/bash

set -e

source "$(dirname "${BASH_SOURCE[0]}")/../git-version.sh"

DEB_REL=0ubuntu1

MAKEFLAGS="-j$(nproc)"

cd python-libnacs
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
      -DPYTHON_EXECUTABLE=/usr/bin/python3 \
      -DCPACK_DEBIAN_PACKAGE_RELEASE=$DEB_REL
set_git_version build

cd build
make
cpack ..
rename_debs .
