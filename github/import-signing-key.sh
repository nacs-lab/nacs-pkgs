#!/bin/bash

# Import the package signing key from `$PACKAGE_SIGNING_KEY` (ASCII armored secret key)
# and cache the passphrase from `$PACKAGE_SIGNING_PASSPHRASE` (optional) in gpg-agent
# so that the packages and the databases can be signed non-interactively.
# The fingerprint of the key is written to `$GITHUB_ENV` as `PACKAGE_SIGNING_KEY_ID`,
# which enables signing in `publish-packages.sh`.

set -e

if [[ -z $PACKAGE_SIGNING_KEY ]]; then
    echo "::warning::PACKAGE_SIGNING_KEY is not set, the packages will not be signed."
    exit 0
fi

export GNUPGHOME=${GNUPGHOME:-$HOME/.gnupg}
mkdir -p -m 700 "$GNUPGHOME"
echo allow-preset-passphrase >> "$GNUPGHOME/gpg-agent.conf"
gpg-connect-agent reloadagent /bye > /dev/null

gpg --batch --import <<< "$PACKAGE_SIGNING_KEY"

keyid=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
if [[ -z $keyid ]]; then
    echo "No secret key found in PACKAGE_SIGNING_KEY" >&2
    exit 1
fi

if [[ -n $PACKAGE_SIGNING_PASSPHRASE ]]; then
    preset=
    for f in /usr/lib/gnupg/gpg-preset-passphrase /usr/libexec/gpg-preset-passphrase; do
        if [[ -x $f ]]; then
            preset=$f
            break
        fi
    done
    if [[ -z $preset ]]; then
        echo "Cannot find gpg-preset-passphrase" >&2
        exit 1
    fi
    gpg --batch --with-colons --with-keygrip --list-secret-keys "$keyid" |
        awk -F: '$1 == "grp" { print $10 }' |
        while read -r keygrip; do
            "$preset" --preset "$keygrip" <<< "$PACKAGE_SIGNING_PASSPHRASE"
        done
fi

# Make sure the key can actually be used for signing.
echo test | gpg --batch --local-user "$keyid" --detach-sign > /dev/null

echo "Imported signing key $keyid"
if [[ -n $GITHUB_ENV ]]; then
    echo "PACKAGE_SIGNING_KEY_ID=$keyid" >> "$GITHUB_ENV"
fi
