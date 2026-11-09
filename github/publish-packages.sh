#!/bin/bash

# Add the packages built for one platform to its package repository on the gh-pages branch
# and copy the PKGBUILD's updated by makepkg back to the source tree.
# Usage: publish-packages.sh <platform> <artifacts dir>

set -e

platform=$1
artifacts=$(realpath "$2")
reponame=nacs

case "$platform" in
    archlinux)
        repodir=archlinux/x86_64
        ;;
    archlinux-arm)
        repodir=archlinux/armv7h
        ;;
    msys2)
        repodir=msys2/mingw64
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

srcdir_of() {
    local name=${1%-package-${platform}}
    case "$platform" in
        archlinux)
            echo "arch/$name"
            ;;
        archlinux-arm)
            echo "arch-arm/$name"
            ;;
        msys2)
            echo "windows/mingw-w64-${name#mingw-w64-x86_64-}"
            ;;
    esac
}

pkgs=()
for artifact in "$artifacts"/*-package-"$platform"/; do
    [[ -d "$artifact" ]] || continue
    artifact=${artifact%/}
    srcdir=$(srcdir_of "${artifact##*/}")
    if [[ -f "$artifact/PKGBUILD" && -f "$srcdir/PKGBUILD" ]]; then
        cp "$artifact/PKGBUILD" "$srcdir/PKGBUILD"
    fi
    found=0
    for pkg in "$artifact"/*.pkg.tar.*; do
        [[ -f "$pkg" ]] || continue
        pkgs+=("$pkg")
        found=1
    done
    if [[ $found = 0 ]]; then
        echo "::warning::No package found in artifact ${artifact##*/}"
    fi
done

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
Add the repository to <code>/etc/pacman.conf</code> to use it.
The packages are not signed.</p>
EOF
    local db repo server pkg
    for db in */*/"$reponame".db; do
        [[ -f "$db" ]] || continue
        repo=${db%/*}
        server="${pages_url}/${repo}"
        case "$repo" in
            archlinux/*)
                server="${pages_url}/${repo%/*}/\$arch"
                ;;
        esac
        cat <<EOF
<h2>${repo}</h2>
<pre>
[${reponame}]
SigLevel = Optional TrustAll
Server = ${server}
</pre>
<ul>
EOF
        for pkg in "$repo"/*.pkg.tar.*; do
            [[ -f "$pkg" ]] || continue
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
        # Remove old versions of the package
        for old in "$repodir"/*.pkg.tar.*; do
            [[ -f "$old" ]] || continue
            if [[ $(pkgname_of "$old") = "$(pkgname_of "$pkg")" ]]; then
                rm "$old"
            fi
        done
        cp -v "$pkg" "$repodir/"
    done

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
        rm -f "$reponame".{db,files}{,.tar.gz,.tar.gz.old}
        repo-add -q "$reponame.db.tar.gz" *.pkg.tar.*
        # GitHub pages does not support symlinks
        for f in "$reponame".{db,files}; do
            cp --remove-destination "$(readlink -f "$f")" "$f"
        done
    )
    touch .nojekyll
    write_index > index.html

    git add -A -f .
    local tree=$(git write-tree)
    cd - > /dev/null

    # Keep only one commit to limit the size of the branch.
    newcommit=$(git commit-tree "$tree" -m "Update ${platform} packages from ${GITHUB_SHA}")
}

# Other platforms may be publishing at the same time.
for ((i = 0; i < 5; i++)); do
    prepare_pages
    if [[ -z "$newcommit" ]]; then
        echo "Package repository is already up to date"
        exit 0
    fi
    if git push --force-with-lease="refs/heads/gh-pages:${oldcommit}" \
           origin "${newcommit}:refs/heads/gh-pages"; then
        exit 0
    fi
    sleep $((RANDOM % 10 + 5))
done
exit 1
