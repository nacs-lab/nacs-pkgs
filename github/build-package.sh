#!/bin/bash

# Build the package in the current directory, similar to lilac (https://github.com/archlinuxcn/lilac).
# Usage: build-package.sh <repo dir> <makepkg command> [<makepkg args>...]
# e.g. build-package.sh archlinux/x86_64 makepkg -s --noconfirm
#
# 1. Download and extract the sources and update the pkgver if needed (`makepkg -o`).
#    Pre-build actions, if there's any in the future, should be run after this.
# 2. If the version of the package is not newer than the one in the package repository
#    on the gh-pages branch, bump the pkgrel to one more than the published one.
# 3. Build the package from the extracted sources (`makepkg -e`).
#    `makepkg` only resets the pkgrel when the pkgver changes so the bumped pkgrel is kept.

set -e

repodir=$1
shift

published_files() {
    local url
    if [[ -n $GITHUB_REPOSITORY ]]; then
        url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}"
    else
        url=$(git -C "$(dirname "${BASH_SOURCE[0]}")" remote get-url origin)
    fi
    local ret=0
    git ls-remote --exit-code --heads "$url" gh-pages > /dev/null || ret=$?
    if [[ $ret = 2 ]]; then
        # Nothing is published yet
        return
    elif [[ $ret != 0 ]]; then
        echo "Failed to check the published packages" >&2
        return $ret
    fi
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    git -C "$tmpdir" fetch -q --depth 1 --filter=blob:none "$url" gh-pages
    git -C "$tmpdir" ls-tree --name-only FETCH_HEAD "$repodir/"
    rm -rf "$tmpdir"
}

# Prints the published version of package $1 from the file list on stdin
published_version() {
    local name=$1 file base ver rel arch extra
    while read -r file; do
        base=${file##*/}
        [[ $base = "$name"-*.pkg.tar.* && $base != *.sig ]] || continue
        base=${base#"$name"-}
        base=${base%.pkg.tar.*}
        # Make sure that we are not matching another package with the same prefix
        IFS=- read -r ver rel arch extra <<< "$base"
        [[ -n $arch && -z $extra ]] || continue
        echo "$ver-$rel"
        return
    done
}

"$@" -o

# Pre-build actions should go here.

pkginfo=$(source ./PKGBUILD && printf '%s\n' "$epoch" "$pkgver" "$pkgrel" "${pkgname[0]}")
{
    read -r epoch
    read -r pkgver
    read -r pkgrel
    read -r name
} <<< "$pkginfo"
fullver="${epoch:+${epoch}:}${pkgver}-${pkgrel}"
files=$(published_files)
pubver=$(published_version "$name" <<< "$files")

if [[ -z $pubver ]]; then
    echo "$name $fullver: not published yet"
elif (( $(vercmp "$fullver" "$pubver") > 0 )); then
    echo "$name $fullver: newer than the published $pubver"
elif [[ ${fullver%-*} = "${pubver%-*}" ]]; then
    pubrel=${pubver##*-}
    newrel=$((${pubrel%%.*} + 1))
    if ! grep -q '^pkgrel=' PKGBUILD; then
        echo "Cannot find pkgrel in PKGBUILD" >&2
        exit 1
    fi
    sed -i "s/^pkgrel=.*/pkgrel=${newrel}/" PKGBUILD
    echo "$name $fullver: already published as $pubver, pkgrel bumped to $newrel"
else
    echo "::warning::$name $fullver is older than the published $pubver"
fi

"$@" -e
