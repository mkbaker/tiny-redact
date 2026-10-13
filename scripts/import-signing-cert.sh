#!/bin/bash
# Imports a code-signing certificate (.p12) into a temporary keychain and prints the identity name.
# Used by the release workflow so every release is signed with the same identity, which keeps
# the Screen Recording permission valid across updates.
#
#   CERT_P12_BASE64=... CERT_PASSWORD=... KEYCHAIN_PATH=... scripts/import-signing-cert.sh
set -euo pipefail

: "${CERT_P12_BASE64:?}" "${CERT_PASSWORD:?}" "${KEYCHAIN_PATH:?}"

KEYCHAIN_PASSWORD="$(uuidgen)"
P12="$(mktemp -t cert).p12"
trap 'rm -f "$P12"' EXIT

echo "$CERT_P12_BASE64" | base64 --decode > "$P12"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 3600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$P12" -k "$KEYCHAIN_PATH" -P "$CERT_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
# Put it first in the search list so codesign finds it.
security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')

# Not -v: a self-signed cert is listed but flagged untrusted, and codesign still accepts it.
security find-identity -p codesigning "$KEYCHAIN_PATH" | sed -n 's/^[^"]*"\([^"]*\)".*/\1/p' | head -1
