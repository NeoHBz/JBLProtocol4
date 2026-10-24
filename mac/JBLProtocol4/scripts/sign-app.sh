#!/usr/bin/env bash
# Usage: sign-app.sh <path.app>. Signs with JBL_SIGN_IDENTITY; every build path goes through here so the app keeps one identity.
#   JBL_STRICT_SIGN=1  refuse to fall back to ad-hoc (release builds)
#   JBL_KEYCHAIN       keychain to search (CI uses a temporary one)
set -euo pipefail
APP="${1:?usage: $0 <path.app>}"
IDENTITY="${JBL_SIGN_IDENTITY:-JBL Control Dev Signing}"
KC=(); [ -n "${JBL_KEYCHAIN:-}" ] && KC=(--keychain "$JBL_KEYCHAIN")
[ -d "$APP" ] || { echo "❌ Not a bundle: $APP" >&2; exit 1; }

if security find-certificate -c "$IDENTITY" ${JBL_KEYCHAIN:+"$JBL_KEYCHAIN"} >/dev/null 2>&1; then
  codesign --force --timestamp=none ${KC[@]+"${KC[@]}"} --sign "$IDENTITY" "$APP" >/dev/null 2>&1 \
    || { echo "❌ codesign failed. If macOS showed a keychain prompt, choose Always Allow and re-run." >&2; exit 1; }
  echo "Signed with \"$IDENTITY\""
elif [ "${JBL_STRICT_SIGN:-0}" = "1" ] && [ "${ALLOW_UNSTABLE_SIGN:-0}" != "1" ]; then
  echo "❌ Signing certificate \"$IDENTITY\" not found. Run 'make cert' once, or ALLOW_UNSTABLE_SIGN=1 for a throwaway build." >&2
  exit 1
else
  codesign --force --sign - "$APP" >/dev/null 2>&1
  echo "⚠️  Signed ad-hoc (no certificate \"$IDENTITY\"). macOS will ask for Bluetooth access again after every rebuild. Fix once with: make cert" >&2
fi
codesign --verify --strict "$APP" && echo "  verified"
