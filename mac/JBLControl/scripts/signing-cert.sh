#!/usr/bin/env bash
# Manage the self-signed code-signing certificate. Commands: create | status | preflight | export | import <file.p12>
# The certificate and its key stay in your keychain. Nothing here is written into the repo.
set -euo pipefail
IDENTITY="${JBL_SIGN_IDENTITY:-JBL Control Dev Signing}"
KEYCHAIN="${JBL_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
die() { printf '❌ %s\n' "$*" >&2; exit 1; }
have() { security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; }

cmd_status() {
  have || die "Certificate \"$IDENTITY\" is not installed. Run: make cert"
  security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" | openssl x509 -noout -subject -enddate | sed 's/^/  /'
}

cmd_create() {
  if have; then echo "Certificate \"$IDENTITY\" already exists. Nothing to do."; return; fi
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 -config "$tmp/openssl.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null || die "openssl failed"
  pass="$(openssl rand -hex 12)"
  openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout "pass:$pass" 2>/dev/null \
    || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout "pass:$pass" \
    || die "could not package the certificate"
  security import "$tmp/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null || die "import failed. Is the keychain unlocked?"
  echo "Created \"$IDENTITY\" in your login keychain."
  echo "The first build may show a keychain prompt. Choose Always Allow."
  echo "Back it up and use it in CI with: make cert-export"
}

cmd_preflight() {
  [ "${ALLOW_UNSTABLE_SIGN:-0}" = "1" ] && return 0
  have || die "Certificate \"$IDENTITY\" not found. Run 'make cert' once (or ALLOW_UNSTABLE_SIGN=1 for a throwaway build)."
}

cmd_export() {
  have || die "Certificate \"$IDENTITY\" is not installed. Run: make cert"
  out="${FILE:-$HOME/jblcontrol-signing.p12}"
  pass="$(openssl rand -hex 12)"
  security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$pass" -o "$out" >/dev/null 2>&1 \
    || die "export failed (keychain may ask you to allow it)"
  chmod 600 "$out"
  echo "Wrote $out (mode 600). This file IS your signing key: keep it where you keep passwords, never in the repo."
  echo "Its password: $pass"
  echo ""
  echo "Store it as GitHub secrets (run once, from inside the repo):"
  echo "  base64 < $out | gh secret set JBL_CERT_P12_BASE64"
  echo "  gh secret set JBL_CERT_PASSWORD --body '$pass'"
  echo "  gh variable set JBL_SIGN_IDENTITY --body '$IDENTITY'"
}

cmd_import() {
  f="${1:?usage: $0 import <file.p12>}"
  read -r -s -p "p12 password: " pass; echo
  security import "$f" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null || die "import failed"
  echo "Imported."
}

case "${1:-}" in
  create) cmd_create ;; status) cmd_status ;; preflight) cmd_preflight ;; export) cmd_export ;;
  import) shift; cmd_import "$@" ;;
  *) echo "usage: $0 create|status|preflight|export|import <file>" >&2; exit 2 ;;
esac
