#!/bin/bash

# Commit the changed PKGBUILD's and push to master.
# Usage: push-master.sh <commit title>

set -e

pkgbuild_ver() {
    # Avoid sourcing the PKGBUILD since some of the variables are platform dependent.
    echo "$(sed -n 's/^pkgver=//p' <<< "$1")-$(sed -n 's/^pkgrel=//p' <<< "$1")"
}

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

msg=$1$'\n'
for f in $(git diff --name-only -- '*/PKGBUILD'); do
    msg+=$'\n'"* ${f%/PKGBUILD}: $(pkgbuild_ver "$(git show "HEAD:$f")") -> $(pkgbuild_ver "$(cat "$f")")"
done

git add -u -- '*/PKGBUILD'
if git diff --cached --quiet; then
    exit 0
fi
git commit -q -m "$msg"

for ((i = 0; i < 5; i++)); do
    git push origin HEAD:master && exit 0
    git pull -q --rebase origin master
done
exit 1
