#!/bin/bash

drivers="$1"
examples="$2"

# ----- see which system is used (32 or 64 bit) -----
CPU_TYPE=`uname -m`
case ${CPU_TYPE} in
    i386)   SYSTEM_WIDTH="32bit";;
    i486)   SYSTEM_WIDTH="32bit";;
    i586)   SYSTEM_WIDTH="32bit";;
    i686)   SYSTEM_WIDTH="32bit";;
    x86_64) SYSTEM_WIDTH="64bit";;
    amd64)  SYSTEM_WIDTH="64bit";;
    *) error_exit "CPU type "${CPU_TYPE}" not supported yet";;
esac

# ----- see which processor type we have (single or SMP) -----
linux_version=`uname -v | grep -o SMP`
case ${linux_version} in
    *SMP*) CPU="smp";;
    *)     CPU="single";;
esac

# ----- check which kernel module we should try to install -----
KERNEL_MODULE_DIR=""
# SUSE
if [ -e /etc/SuSE-release ]; then
    KERNEL_MODULE_DIR=suse`grep VERSION /etc/SuSE-release|sed 's/[^0-9]*\([0-9]*\).\([0-9]\)/\1\2/'`_${SYSTEM_WIDTH}_$CPU
    FORMAT=RPM

    # Fedora
elif [ -e /etc/fedora-release ]; then
    KERNEL_MODULE_DIR=fedora`cat /etc/fedora-release | sed 's/[^0-9]*\([0-9]*\)[^0-9]*/\1/'`_${SYSTEM_WIDTH}_$CPU
    FORMAT=RPM

    # Redhat
elif [ -e /etc/redhat-release ]; then
    KERNEL_MODULE_DIR=redhat`grep -o -e [0-9] /etc/redhat-release`0_${SYSTEM_WIDTH}_$CPU
    FORMAT=RPM

    # Debian/Ubuntu
elif [ -e /etc/debian_version ]; then
    # check for ubuntu
    if [ -e /usr/bin/lsb_release ]; then
        DISTRI=`lsb_release -is`
        if [ "$DISTRI" = "Ubuntu" ]; then
            KERNEL_MODULE_DIR=ubuntu_`lsb_release -rs`_${SYSTEM_WIDTH}_$CPU
        elif [ "$DISTRI" = "Debian" ]; then
            DEB_VER=`lsb_release -rs`
            if [[ $DEB_VER == 9.* ]]; then
                # ***** Debian 9.x Stretch
                echo "Debian 9.x Stretch found"
                KERNEL_MODULE_DIR=debian_90_stretch_${SYSTEM_WIDTH}_$CPU
            elif [[ $DEB_VER == 8.* ]]; then
                # ***** Debian 8.x Jessie
                echo "Debian 8.x Jessie found"
                KERNEL_MODULE_DIR=debian_80_jessie_${SYSTEM_WIDTH}_$CPU
            elif [[ $DEB_VER == 7.* ]]; then
                # ***** Debian 7.x Wheezy
                echo "Debian 7.x Wheezy found"
                KERNEL_MODULE_DIR=debian_70_wheezy_${SYSTEM_WIDTH}_$CPU
            elif [[ $DEB_VER == 6.* ]]; then
                # ***** Debian 6.x Squeeze
                echo "Debian 6.x Squeeze found"
                KERNEL_MODULE_DIR=debian_60_squeeze_${SYSTEM_WIDTH}_$CPU
            fi
        fi
    else
        # ***** if debian *****
        DEB_VER=`cat /etc/debian_version`

        if [[ $DEB_VER == 7.* ]]; then
            # ***** Debian 7.x Wheezy
            echo "Debian 7.x Wheezy found"
            KERNEL_MODULE_DIR=debian_70_wheezy_${SYSTEM_WIDTH}_$CPU
        elif [[ $DEB_VER == 6.* ]]; then
            # ***** Debian 6.x Squeeze
            echo "Debian 6.x Squeeze found"
            KERNEL_MODULE_DIR=debian_60_squeeze_${SYSTEM_WIDTH}_$CPU
        elif [[ $DEB_VER == 5.* ]]; then
            # ***** Debian 5.x Lenny
            echo "Debian 5.x Lenny found"
            KERNEL_MODULE_DIR=debian_50_lenny_${SYSTEM_WIDTH}_$CPU
        elif [[ $DEB_VER == 4.* ]]; then
            # ***** Debian 4.x Etch
            echo "Debian 4.x Etch found"
            KERNEL_MODULE_DIR=debian_40_etch_${SYSTEM_WIDTH}_$CPU
        elif [ "$DEB_VER" = "3.1" ]; then
            # ***** Debian 3.1 Sarge
            echo "Debian 3.1 Sarge found"
            if [ "`uname -r|grep -o 2.6.8`" = "2.6.8" ]; then
                KERNEL_MODULE_DIR=debian_31_sarge2608_${SYSTEM_WIDTH}_$CPU
            elif [ "`uname -r|grep -o 2.4.27`" = "2.4.27" ]; then
                KERNEL_MODULE_DIR=debian_31_sarge2427_${SYSTEM_WIDTH}_$CPU
            fi
        fi
    fi
    FORMAT=DEB
fi

if [ "$KERNEL_MODULE_DIR" == "" ]; then
    echo "Unable to find kernel module"
    exit 1
elif [ "$FORMAT" != "DEB" ]; then
    echo "Only Debian based distro supported by this script."
else
    echo "Trying to install kernel modules from $KERNEL_MODULE_DIR"
fi

echo "Clearing workspace"
rm -rf unpack deb pkg
mkdir -pv unpack deb pkg

tar -C unpack -xf "$drivers"
tar -C unpack -xf "$examples"

if [ "${SYSTEM_WIDTH}" == "32bit" ]; then
    cp -v unpack/spcm_linux/libs/libspcm-linux-*.i386.deb deb
else
    cp -v unpack/spcm_linux/libs/libspcm-linux-*.amd64.deb deb
fi
cp -v unpack/spcm_linux/$KERNEL_MODULE_DIR/spcm*.deb deb

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
cp -v unpack/spcm_examples/c_cpp/c_header/*.{h,inc} $pkgdir/usr/include/spcm/
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

sudo dpkg -i deb/*.deb
