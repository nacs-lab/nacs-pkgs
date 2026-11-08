#!/bin/bash

# Copy already published packages from the gh-pages branch
# to be used in place of a newly built one.
# Usage: fetch-published.sh <repo dir> <destination> <package glob>...

set -e

repodir=$1
dest=$2
shift 2

if ! command -v git > /dev/null && command -v pacman > /dev/null; then
    # ArchLinux container without the build setup
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Syu --noconfirm git
fi

patterns=()
for pattern in "$@"; do
    patterns+=("/${repodir}/${pattern}")
done

tmpdir=$(mktemp -d)
git -C "$tmpdir" init -q
git -C "$tmpdir" remote add origin "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
git -C "$tmpdir" sparse-checkout set --no-cone "${patterns[@]}"
git -C "$tmpdir" fetch -q --depth 1 --filter=blob:none origin gh-pages
git -C "$tmpdir" checkout -q FETCH_HEAD

mkdir -p "$dest"
cp -v "$tmpdir/$repodir"/*.pkg.tar.* "$dest"/
rm -rf "$tmpdir"
