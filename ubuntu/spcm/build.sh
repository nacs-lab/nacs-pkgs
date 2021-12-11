#!/bin/bash

drv_ver=527
ubuntu_rel=${1:-$(lsb_release -rs)}

echo "Building for Ubuntu ${ubuntu_rel}"

echo "Clearing workspace"
rm -rf download unpack deb pkg
mkdir -pv download unpack deb pkg

wget -P download \
     https://spectrum-instrumentation.com/sites/default/files/download/spcm_linux_drv_v$drv_ver.tgz
wget -P download \
     https://spectrum-instrumentation.com/sites/default/files/download/spcm_examples.tgz

tar -C unpack -xf download/spcm_linux_drv_v$drv_ver.tgz
tar -C unpack -xf download/spcm_examples.tgz

cp -v unpack/spcm_linux/libs/libspcm-linux-*.amd64.deb deb
cp -v unpack/spcm_linux/ubuntu_${ubuntu_rel}_64bit_smp/spcm*.deb deb

lib_name=(deb/libspcm-linux-*.deb)
if [ ${#lib_name[@]} != 1 ] || \
       ! [[ $lib_name =~ .*/libspcm-linux-([^.-]*\.[^.-]*-[^.-]*)\.([^.-]*)\.deb ]]; then
    echo "Cannot determine library version"
    exit 1
fi

echo "Creating dev package"
lib_ver=${BASH_REMATCH[1]}
arch=${BASH_REMATCH[2]}
pkgdir=pkg/libspcm-linux-dev_$lib_ver
mkdir $pkgdir
mkdir -p $pkgdir/usr/include/spcm/
cp -v unpack/spcm_examples/c_cpp/c_header/*.h $pkgdir/usr/include/spcm/
rm $pkgdir/usr/include/spcm/{errors.h,spectrum.h}
cat > $pkgdir/usr/include/spcm/spcm.h <<EOF
// Header to include all needed headers since the driver library header needs to be
// included in the right order....
// Unclear why they are not more user friendly.
#include "dlltyp.h"
#include "regs.h"
#include "spcerr.h"
#include "spcm_drv.h"
EOF
mkdir $pkgdir/DEBIAN
cat > $pkgdir/DEBIAN/control <<EOF
Package: libspcm-linux-dev
Version: $lib_ver
Section: base
Priority: optional
Architecture: $arch
Depends: libspcm-linux (= $lib_ver)
Maintainer: Yichao Yu <yyc1992@gmail.com>
Description: Header for libspcm
EOF
fakeroot dpkg-deb --build $pkgdir
mv -v pkg/libspcm-linux-dev_$lib_ver.deb deb/libspcm-linux-dev_$lib_ver.$arch.deb
