#!/bin/bash
# Manages the optional local code signing identity for source builds.
#
# An ad-hoc signature identifies the app by the hash of one specific build, so
# macOS treats every rebuilt app as a new program: the Keychain grant for the
# NAS password and the privacy grant for network volumes are lost on each
# update. A self-signed identity gives all local builds the same designated
# requirement (bundle identifier plus certificate), so both grants survive.
#
# The identity is only meaningful on the Mac that created it. It is not an
# Apple-issued identity and cannot carry restricted entitlements.
#
#   local-signing-identity.sh resolve   print the identity name, or "-" for ad-hoc
#   local-signing-identity.sh create    create the identity in the login keychain
#   local-signing-identity.sh status    describe the current state
set -euo pipefail

IDENTITY_NAME="${GDRIVE_LOCAL_SIGN_IDENTITY:-GDrive Backup Tiger Local Signing}"
VALID_DAYS=3650
WORK_DIR=""

identity_exists() {
  /usr/bin/security find-certificate -c "$IDENTITY_NAME" >/dev/null 2>&1 &&
    /usr/bin/security find-identity -p codesigning 2>/dev/null |
      /usr/bin/grep -Fq "\"$IDENTITY_NAME\""
}

resolve() {
  if [[ "${GDRIVE_FORCE_ADHOC_SIGNATURE:-0}" == "1" ]]; then
    printf '%s\n' '-'
  elif identity_exists; then
    printf '%s\n' "$IDENTITY_NAME"
  else
    printf '%s\n' '-'
  fi
}

create() {
  if identity_exists; then
    printf 'Signing identity already exists: %s\n' "$IDENTITY_NAME"
    return 0
  fi

  local keychain passphrase
  # The private key exists on disk only inside this directory until imported.
  # WORK_DIR is global because the EXIT trap runs after this function returned.
  WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-signing-identity.XXXXXX")"
  /bin/chmod 700 "$WORK_DIR"
  trap '/bin/rm -rf "$WORK_DIR"' EXIT
  local work="$WORK_DIR"
  keychain="$(/usr/bin/security default-keychain -d user | /usr/bin/sed -E 's/^[[:space:]]*"(.*)"$/\1/')"
  passphrase="$(/usr/bin/openssl rand -hex 24)"

  /bin/cat >"$work/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY_NAME
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days "$VALID_DAYS" \
    -config "$work/openssl.cnf" \
    -keyout "$work/identity.key" -out "$work/identity.crt" >/dev/null 2>&1
  /usr/bin/openssl pkcs12 -export -name "$IDENTITY_NAME" \
    -inkey "$work/identity.key" -in "$work/identity.crt" \
    -out "$work/identity.p12" -passout "pass:$passphrase" >/dev/null 2>&1
  /usr/bin/security import "$work/identity.p12" -k "$keychain" \
    -P "$passphrase" -T /usr/bin/codesign >/dev/null

  if ! identity_exists; then
    printf '%s\n' 'The signing identity could not be created.' >&2
    return 1
  fi
  printf 'Created signing identity: %s\n' "$IDENTITY_NAME"
  printf '%s\n' 'macOS asks once for permission when codesign first uses the key; choose "Always Allow".'
}

status() {
  if identity_exists; then
    printf 'Local signing identity present: %s\n' "$IDENTITY_NAME"
  else
    printf '%s\n' 'No local signing identity; source builds are signed ad-hoc.'
  fi
}

case "${1:-}" in
  resolve) resolve ;;
  create) create ;;
  status) status ;;
  *)
    printf 'Usage: %s resolve|create|status\n' "${0##*/}" >&2
    exit 64
    ;;
esac
