#!/bin/bash

# Add the packages from the build artifacts to the package repositories
# and copy the PKGBUILD's updated by makepkg back to the source tree.
# Usage: publish-packages.sh <artifacts dir> <repository dir>

set -e

artifacts=$(realpath "$1")
pages=$(realpath "$2")
srcroot=$PWD
reponame=nacs

pkgname_of() {
    local base=${1##*/}
    base=${base%.pkg.tar.*}
    echo "${base%-*-*-*}"
}

for artifact in "$artifacts"/*/; do
    artifact=${artifact%/}
    name=${artifact##*/}
    case "$name" in
        *-package-archlinux-arm)
            repodir=archlinux-arm/armv7h
            srcdir=arch-arm/${name%-package-archlinux-arm}
            ;;
        *-package-archlinux)
            repodir=archlinux/x86_64
            srcdir=arch/${name%-package-archlinux}
            ;;
        mingw-w64-x86_64-*-package-msys2)
            repodir=msys2/mingw64
            name=${name%-package-msys2}
            srcdir=windows/mingw-w64-${name#mingw-w64-x86_64-}
            ;;
        *)
            echo "Ignoring unknown artifact $name"
            continue
            ;;
    esac

    if [[ -f "$artifact/PKGBUILD" && -f "$srcroot/$srcdir/PKGBUILD" ]]; then
        cp "$artifact/PKGBUILD" "$srcroot/$srcdir/PKGBUILD"
    fi

    mkdir -p "$pages/$repodir"
    for pkg in "$artifact"/*.pkg.tar.*; do
        [[ -f "$pkg" ]] || continue
        pkgname=$(pkgname_of "$pkg")
        # Remove old versions of the package
        for old in "$pages/$repodir"/*.pkg.tar.*; do
            [[ -f "$old" ]] || continue
            if [[ $(pkgname_of "$old") = "$pkgname" ]]; then
                rm "$old"
            fi
        done
        cp -v "$pkg" "$pages/$repodir/"
    done
done

cd "$pages"

repos=()
for db in */*/"$reponame".db.tar.gz */*/*.pkg.tar.*; do
    [[ -f "$db" ]] && repos+=("${db%/*}")
done
readarray -t repos < <(printf '%s\n' "${repos[@]}" | sort -u)

for repodir in "${repos[@]}"; do
    (
        cd "$repodir"
        # Recreate the database so that it matches the packages exactly.
        rm -f "$reponame".{db,files}{,.tar.gz,.tar.gz.old}
        pkgs=(*.pkg.tar.*)
        if [[ -f "${pkgs[0]}" ]]; then
            repo-add -q "$reponame.db.tar.gz" "${pkgs[@]}"
            # GitHub pages does not support symlinks
            for f in "$reponame".{db,files}; do
                cp --remove-destination "$(readlink -f "$f")" "$f"
            done
        fi
    )
done

pages_url="https://${GITHUB_REPOSITORY_OWNER,,}.github.io/${GITHUB_REPOSITORY#*/}"

touch .nojekyll
{
    cat <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>NaCs packages</title>
</head>
<body>
<h1>NaCs packages</h1>
<p>Built from <a href="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}">${GITHUB_REPOSITORY}</a>.
Add the repository to <code>/etc/pacman.conf</code> to use it.
The packages are not signed.</p>
EOF
    for repodir in "${repos[@]}"; do
        server="${pages_url}/${repodir}"
        case "$repodir" in
            archlinux/*|archlinux-arm/*)
                server="${pages_url}/${repodir%/*}/\$arch"
                ;;
        esac
        cat <<EOF
<h2>${repodir}</h2>
<pre>
[${reponame}]
SigLevel = Optional TrustAll
Server = ${server}
</pre>
<ul>
EOF
        for pkg in "$repodir"/*.pkg.tar.*; do
            [[ -f "$pkg" ]] || continue
            echo "<li><a href=\"${pkg}\">${pkg##*/}</a></li>"
        done
        echo "</ul>"
    done
    cat <<EOF
</body>
</html>
EOF
} > index.html
