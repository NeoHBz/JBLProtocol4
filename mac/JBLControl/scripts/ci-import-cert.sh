#!/usr/bin/env bash
# CI only. Imports the signing certificate from Actions secrets into a throwaway keychain and prints
# JBL_KEYCHAIN to GITHUB_ENV. Does nothing (the build then signs ad-hoc) if the secrets are not set,
# e.g. on pull requests from forks.
set -euo pipefail
if [ -z "${JBL_CERT_P12_BASE64:-}" ] || [ -z "${JBL_CERT_PASSWORD:-}" ]; then
  echo "No signing secrets present, building ad-hoc."; exit 0
fi
KC="$RUNNER_TEMP/jbl-signing.keychain-db"
KCPASS="$(openssl rand -hex 16)"
echo "::add-mask::$KCPASS"
printf '%s' "$JBL_CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/id.p12"
security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KCPASS" "$KC"
security import "$RUNNER_TEMP/id.p12" -k "$KC" -P "$JBL_CERT_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
rm -f "$RUNNER_TEMP/id.p12"
echo "JBL_KEYCHAIN=$KC" >> "$GITHUB_ENV"
echo "Signing certificate imported into a temporary keychain."
