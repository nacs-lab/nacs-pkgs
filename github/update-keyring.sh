#!/bin/bash

# Update the trusted keys in the nacs-keyring package from the local gpg keyring.
# Usage: update-keyring.sh <key id>...
#
# All the keys listed are trusted. To revoke a key, keep it in the list
# and add its fingerprint to `arch/nacs-keyring/nacs-revoked` afterwards.
# The package is rebuilt automatically when the keys change.

set -e

if [[ $# = 0 ]]; then
    echo "Usage: $0 <key id>..." >&2
    exit 1
fi

dir=$(dirname "${BASH_SOURCE[0]}")/../arch/nacs-keyring

fprs=()
for key in "$@"; do
    fpr=$(gpg --batch --with-colons --list-keys "$key" | awk -F: '$1 == "fpr" { print $10; exit }')
    if [[ -z $fpr ]]; then
        echo "Cannot find key $key" >&2
        exit 1
    fi
    fprs+=("$fpr")
done

gpg --batch --armor --export "${fprs[@]}" > "$dir/nacs.gpg"
revoked=$(cat "$dir/nacs-revoked" 2> /dev/null || true)
: > "$dir/nacs-trusted"
for fpr in "${fprs[@]}"; do
    if ! grep -qx "$fpr" <<< "$revoked"; then
        echo "$fpr:4:" >> "$dir/nacs-trusted"
    fi
done
touch "$dir/nacs-revoked"
sed -i -e "s/^pkgver=.*/pkgver=$(date +%Y%m%d)/" -e "s/^pkgrel=.*/pkgrel=1/" "$dir/PKGBUILD"

echo "Updated $dir:"
cat "$dir/nacs-trusted"
