#!/usr/bin/env bash
#
# Fetch the vendored `libidevice_ffi.a` static library and verify its SHA-256.
#
# The library is ~92.6 MB and arm64/iOS-only, so it is not checked into git.
# It is taken verbatim from TLocation at the pinned upstream commit (the same
# commit this repository ports its location-injection engine from):
#
#   https://github.com/truongkma/t-location/commit/5e57f815e5958f133dfbaae8252473054adeccf0
#
# Usage:
#   bash scripts/fetch-vendor.sh          # download if missing/invalid
#   bash scripts/fetch-vendor.sh --force  # always re-download
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT_DIR}/Vendor/idevice/libidevice_ffi.a"
URL="https://raw.githubusercontent.com/truongkma/t-location/5e57f815e5958f133dfbaae8252473054adeccf0/TLocation/idevice/libidevice_ffi.a"
SHA256="6524066d54ef23e00d46445c04dfc694e180196d54119d718f68434fa225be35"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "error: neither shasum nor sha256sum is available" >&2
    exit 1
  fi
}

if [[ -f "${DEST}" && "${FORCE}" -eq 0 ]]; then
  CURRENT="$(sha256_of "${DEST}")"
  if [[ "${CURRENT}" == "${SHA256}" ]]; then
    echo "libidevice_ffi.a already present and verified (${SHA256})."
    exit 0
  fi
  echo "Existing libidevice_ffi.a has the wrong SHA-256; re-downloading." >&2
fi

mkdir -p "$(dirname "${DEST}")"
TMP="${DEST}.tmp"
rm -f "${TMP}"

echo "Downloading libidevice_ffi.a (about 92.6 MB)…"
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 --retry-delay 2 -o "${TMP}" "${URL}"
elif command -v wget >/dev/null 2>&1; then
  wget -O "${TMP}" "${URL}"
else
  echo "error: neither curl nor wget is available" >&2
  exit 1
fi

ACTUAL="$(sha256_of "${TMP}")"
if [[ "${ACTUAL}" != "${SHA256}" ]]; then
  rm -f "${TMP}"
  echo "error: SHA-256 mismatch for libidevice_ffi.a" >&2
  echo "  expected: ${SHA256}" >&2
  echo "  actual:   ${ACTUAL}" >&2
  exit 1
fi

mv "${TMP}" "${DEST}"
echo "Verified and installed: ${DEST}"
