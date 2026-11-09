#!/bin/bash

# Helpers for building the Debian packages from git repositories with CPack.
# Source this file and call the functions in the source directory of the project.

# Set the Debian package version to `<project version>+git<commit count>.<short hash>`
# (same commit count and hash as the `pkgver` of the ArchLinux packages).
# Usage: set_git_version <build dir>
# The build directory must already be configured.
set_git_version() {
    local builddir=$1 basever
    basever=$(sed -n 's/^set(CPACK_PACKAGE_VERSION "\(.*\)")$/\1/p' "$builddir/CPackConfig.cmake")
    if [[ -z $basever ]]; then
        echo "Cannot find the package version in $builddir/CPackConfig.cmake" >&2
        return 1
    fi
    if [[ $(git rev-parse --is-shallow-repository) = true ]]; then
        echo "The full git history is needed to compute the version" >&2
        return 1
    fi
    local version="${basever}+git$(git rev-list --count HEAD).$(git rev-parse --short HEAD)"
    echo "Package version: $version"
    cmake -B "$builddir" -DCPACK_DEBIAN_PACKAGE_VERSION="$version"
}

# The package file name set by the projects doesn't include the git version.
# Rename the packages to `<name>_<version>_<arch>.deb`.
# Usage: rename_debs <dir>
rename_debs() {
    local deb name version arch dest
    for deb in "$1"/*.deb; do
        [[ -f $deb ]] || continue
        name=$(dpkg-deb -f "$deb" Package)
        version=$(dpkg-deb -f "$deb" Version)
        arch=$(dpkg-deb -f "$deb" Architecture)
        dest="$1/${name}_${version#*:}_${arch}.deb"
        if [[ $deb != "$dest" ]]; then
            mv -v "$deb" "$dest"
        fi
    done
}
