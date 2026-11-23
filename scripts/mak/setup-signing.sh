#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Part of macArmyKnife, a modified version of Vorssaint
# (https://github.com/vorssaint/vorssaint-utils), changed 2026-11-23.
#
# Creates (once) the free, self-signed "macArmyKnife Signing" certificate that
# every macArmyKnife build is signed with, in its own keychain file. Modeled on
# Tools/setup-signing.sh but deliberately separate: that script owns
# vorssaint-signing.keychain-db and deletes it when it reissues, and this one
# must never touch the Vorssaint identity.
#
# Signing every build with the same certificate keeps macOS permission grants
# (Accessibility, Screen Recording, Full Disk Access) attached across updates.
# Idempotent: exits early when the identity already signs.
set -euo pipefail

IDENTITY="macArmyKnife Signing"
KC="$HOME/Library/Keychains/macarmyknife-signing.keychain-db"
# Local-only keychain holding one self-signed code-signing key; the password
# only lets scripted builds unlock it, as Tools/setup-signing.sh does.
KCPASS="macarmyknife-signing"

identity_can_sign() {
    local probe signed=1
    # Locked after every reboot; a locked keychain cannot sign.
    security unlock-keychain -p "$KCPASS" "$KC" 2>/dev/null || true
    probe="$(mktemp)"
    cp /bin/echo "$probe"
    codesign --force --strip-disallowed-xattrs --sign "$IDENTITY" "$probe" >/dev/null 2>&1 && signed=0
    rm -f "$probe"
    return $signed
}

if identity_can_sign; then
    echo "✓ macArmyKnife signing identity ready."
    exit 0
fi

if [[ -e "$KC" ]]; then
    # Never reissue silently: a new certificate would orphan every permission
    # macOS granted to the old one. Stop and let a person decide.
    echo "✗ $KC exists but cannot sign as '$IDENTITY'." >&2
    echo "  Not replacing it automatically (permission grants are tied to it)." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -nodes \
    -subj "/CN=$IDENTITY/O=macArmyKnife" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass:"$KCPASS" -name "$IDENTITY" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock
security unlock-keychain -p "$KCPASS" "$KC"
security import "$WORK/id.p12" -k "$KC" -P "$KCPASS" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null 2>&1

EXISTING=$(security list-keychains -d user | sed 's/"//g' | xargs)
security list-keychains -d user -s "$KC" ${=EXISTING}

identity_can_sign || {
    echo "✗ Identity imported but codesign cannot sign with it." >&2
    exit 1
}
echo "✓ Created signing identity '$IDENTITY'."
