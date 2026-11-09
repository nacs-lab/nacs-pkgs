#!/bin/bash

# Add the packages built for one platform to its package repository on the gh-pages branch
# and copy the PKGBUILD's updated by makepkg back to the source tree.
# Usage: publish-packages.sh <platform> <artifacts dir>
#
# If `$PACKAGE_SIGNING_KEY_ID` is set (see `import-signing-key.sh`), the packages
# (including the already published ones without a signature) and the databases are signed
# and the public key is published as `nacs.asc`.

set -e

platform=$1
artifacts=$(realpath "$2")
# The public key is shared by all repositories.
keyfile=nacs.asc

# Each MSYS2 environment needs a different repository name
# so that they can be used at the same time.
# The package ids (see `check-updates.py`) have a suffix for these environments.
idsuffix=
case "$platform" in
    archlinux)
        repodir=archlinux/x86_64
        reponame=nacs
        srcroot=arch
        ;;
    archlinux-arm)
        repodir=archlinux/armv7h
        reponame=nacs
        srcroot=arch-arm
        ;;
    msys2)
        repodir=msys2/mingw64
        reponame=nacs
        srcroot=windows
        ;;
    msys2-ucrt64|msys2-clang64)
        repodir=msys2/${platform#msys2-}
        reponame=nacs-${platform#msys2-}
        srcroot=windows
        idsuffix=@${platform#msys2-}
        ;;
    *)
        echo "Unknown platform $platform" >&2
        exit 1
        ;;
esac

pkgname_of() {
    local base=${1##*/}
    base=${base%.pkg.tar.*}
    echo "${base%-*-*-*}"
}

# The PKGBUILD directories are named after the pkgbase.
pkgbase_of() {
    bsdtar -xOf "$1" .PKGINFO | sed -n 's/^pkgbase = //p'
}

# Don't rely on the artifact directory names since download-artifact
# doesn't create a subdirectory when only one artifact is downloaded.
# Prints the packages (not the signatures) in the arguments
filter_pkgs() {
    local f
    for f in "$@"; do
        [[ $f = *.sig ]] || echo "$f"
    done
}

shopt -s globstar nullglob
mapfile -t pkgs < <(filter_pkgs "$artifacts"/**/*.pkg.tar.*)
# Ids of the packages published, used to record the versions built in the update workflow.
published=()
for pkgbuild in "$artifacts"/**/PKGBUILD; do
    dir=${pkgbuild%/PKGBUILD}
    mapfile -t dirpkgs < <(filter_pkgs "$dir"/*.pkg.tar.*)
    if [[ ${#dirpkgs[@]} = 0 ]]; then
        echo "::warning::No package found next to ${pkgbuild#"$artifacts"/}"
        continue
    fi
    srcdir="$srcroot/$(pkgbase_of "${dirpkgs[0]}")"
    if [[ -f "$srcdir/PKGBUILD" ]]; then
        cp "$pkgbuild" "$srcdir/PKGBUILD"
        published+=("$srcdir$idsuffix")
    else
        echo "::warning::Cannot find $srcdir/PKGBUILD for ${pkgbuild#"$artifacts"/}"
    fi
done
shopt -u globstar nullglob

if [[ ${#pkgs[@]} = 0 ]]; then
    echo "No packages to publish"
    exit 0
fi

# Use a temporary index and work tree with the main repository
# so that the credentials from the checkout can be used.
export GIT_DIR=$(git rev-parse --absolute-git-dir)
tmpdir=$(mktemp -d)
export GIT_INDEX_FILE="$tmpdir/index"
export GIT_WORK_TREE="$tmpdir/pages"

export GIT_AUTHOR_NAME="github-actions[bot]"
export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

write_index() {
    local pages_url="https://${GITHUB_REPOSITORY_OWNER,,}.github.io/${GITHUB_REPOSITORY#*/}"
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
Add the repository to <code>/etc/pacman.conf</code> to use it.</p>
EOF
    local siglevel=
    if [[ -n $PACKAGE_SIGNING_KEY_ID ]]; then
        cat <<EOF
<p>The packages and the databases are signed with the key
<a href="${keyfile}"><code>${PACKAGE_SIGNING_KEY_ID}</code></a>.
Import it before using the repository with</p>
<pre>
curl -O ${pages_url}/${keyfile}
pacman-key --add ${keyfile}
pacman-key --lsign-key ${PACKAGE_SIGNING_KEY_ID}
</pre>
<p>After adding the repository, install <code>nacs-keyring</code>
to keep the key up to date.</p>
<pre>
pacman -Sy nacs-keyring
</pre>
EOF
    else
        echo "<p>The packages are not signed.</p>"
        siglevel=$'\nSigLevel = Optional TrustAll'
    fi
    local db repo name server pkg
    for db in */*/*.db; do
        [[ -f "$db" ]] || continue
        repo=${db%/*}
        name=${db##*/}
        name=${name%.db}
        server="${pages_url}/${repo}"
        case "$repo" in
            archlinux/*)
                server="${pages_url}/${repo%/*}/\$arch"
                ;;
        esac
        cat <<EOF
<h2>${repo}</h2>
<pre>
[${name}]${siglevel}
Server = ${server}
</pre>
<ul>
EOF
        for pkg in "$repo"/*.pkg.tar.*; do
            [[ -f "$pkg" && $pkg != *.sig ]] || continue
            echo "<li><a href=\"${pkg}\">${pkg##*/}</a></li>"
        done
        echo "</ul>"
    done
    cat <<EOF
</body>
</html>
EOF
}

# Sets `oldcommit` to the current gh-pages commit (empty if it doesn't exist)
# and `newcommit` to the updated one (empty if nothing changed).
prepare_pages() {
    rm -rf "$GIT_WORK_TREE" "$GIT_INDEX_FILE"
    mkdir -p "$GIT_WORK_TREE"

    oldcommit=
    git ls-remote --exit-code --heads origin gh-pages > /dev/null && ret=0 || ret=$?
    if [[ $ret = 0 ]]; then
        git fetch -q origin +refs/heads/gh-pages:refs/remotes/origin/gh-pages
        oldcommit=$(git rev-parse refs/remotes/origin/gh-pages)
        git read-tree "$oldcommit"
        git checkout-index -a
    elif [[ $ret != 2 ]]; then
        exit $ret
    fi

    cd "$GIT_WORK_TREE"
    mkdir -p "$repodir"
    local pkg old
    for pkg in "${pkgs[@]}"; do
        # Keep the package (and its signature) if it's already published
        if cmp -s "$pkg" "$repodir/${pkg##*/}"; then
            continue
        fi
        # Remove old versions of the package (and their signatures)
        for old in "$repodir"/*.pkg.tar.*; do
            [[ -f "$old" ]] || continue
            if [[ $(pkgname_of "$old") = "$(pkgname_of "$pkg")" ]]; then
                rm "$old"
            fi
        done
        cp -v "$pkg" "$repodir/"
    done
    if [[ -n $PACKAGE_SIGNING_KEY_ID ]]; then
        for pkg in "$repodir"/*.pkg.tar.*; do
            [[ -f $pkg && $pkg != *.sig && ! -f $pkg.sig ]] || continue
            echo "Signing ${pkg##*/}"
            gpg --batch --yes --local-user "$PACKAGE_SIGNING_KEY_ID" \
                --detach-sign --no-armor "$pkg"
        done
    fi

    newcommit=
    # The database changes every time it's generated so check the packages instead.
    git add -A -f "$repodir"
    if [[ -n "$oldcommit" ]] && git diff --cached --quiet "$oldcommit" -- "$repodir"; then
        cd - > /dev/null
        return
    fi

    (
        cd "$repodir"
        # Recreate the database so that it matches the packages exactly.
        rm -f "$reponame".{db,files}{,.tar.gz,.tar.gz.old}{,.sig}
        sign=()
        if [[ -n $PACKAGE_SIGNING_KEY_ID ]]; then
            sign=(--sign --key "$PACKAGE_SIGNING_KEY_ID")
        fi
        mapfile -t files < <(filter_pkgs *.pkg.tar.*)
        repo-add -q "${sign[@]}" "$reponame.db.tar.gz" "${files[@]}"
        # GitHub pages does not support symlinks
        for f in "$reponame".{db,files}{,.sig}; do
            [[ -L $f ]] || continue
            cp --remove-destination "$(readlink -f "$f")" "$f"
        done
    )
    touch .nojekyll
    if [[ -n $PACKAGE_SIGNING_KEY_ID ]]; then
        gpg --batch --armor --export "$PACKAGE_SIGNING_KEY_ID" > "$keyfile"
    fi
    write_index > index.html

    git add -A -f .
    local tree=$(git write-tree)
    cd - > /dev/null

    # Keep only one commit to limit the size of the branch.
    newcommit=$(git commit-tree "$tree" -m "Update ${platform} packages from ${GITHUB_SHA}")
}

finish() {
    if [[ -n $GITHUB_OUTPUT ]]; then
        echo "published=${published[*]}" >> "$GITHUB_OUTPUT"
    fi
    exit 0
}

# Other platforms may be publishing at the same time.
for ((i = 0; i < 5; i++)); do
    prepare_pages
    if [[ -z "$newcommit" ]]; then
        echo "Package repository is already up to date"
        finish
    fi
    if git push --force-with-lease="refs/heads/gh-pages:${oldcommit}" \
           origin "${newcommit}:refs/heads/gh-pages"; then
        finish
    fi
    sleep $((RANDOM % 10 + 5))
done
exit 1
