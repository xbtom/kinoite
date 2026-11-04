#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../lib/network.sh"

echo "Installing TUXEDO Control Center..."
dnf5 install -y libayatana-appindicator-gtk3

FEDORA_VER="$(rpm -E %fedora)"
TUX_BASE_URL="https://rpm.tuxedocomputers.com/fedora/${FEDORA_VER}/x86_64/base"
TUX_KEY_URL="https://rpm.tuxedocomputers.com/fedora/${FEDORA_VER}/0x54840598.pub.asc"
# Short key ID of the TUXEDO signing key (the package is signed with
# 120ed28d54840598); used below to confirm the import actually landed.
TUX_KEY_ID="54840598"

RPM_FILE=/tmp/tuxedo-control-center.rpm
KEY_FILE=/tmp/tuxedo-signing-key.pub.asc
LISTING_FILE=/tmp/tuxedo-control-center.listing.html
trap 'rm -f "${RPM_FILE}" "${KEY_FILE}" "${LISTING_FILE}"' EXIT

# Find the newest package in the repository listing. fetch retries transient
# errors first, so a failure here means the listing is really unavailable (or
# has no package), not that we hit one network hiccup. sort -V keeps version
# order correct (3.1.10 is newer than 3.1.9).
TCC_RPM_NAME=""
if fetch "${TUX_BASE_URL}/" "${LISTING_FILE}"; then
    TCC_RPM_NAME="$(grep -oE 'href="tuxedo-control-center_[^"]+\.rpm"' "${LISTING_FILE}" | sort -V | tail -n 1 | cut -d'"' -f2)" || TCC_RPM_NAME=""
fi

# Without a package name the download URL would point at the directory
# itself and fail with a confusing error, so stop here with a clear one.
if [[ -z "${TCC_RPM_NAME}" ]]; then
    echo "ERROR: could not determine the TUXEDO Control Center rpm name from ${TUX_BASE_URL}/" >&2
    exit 1
fi

RPM_DOWNLOAD_URL="${TUX_BASE_URL}/${TCC_RPM_NAME}"

# Newer rpm refuses packages signed by a key that is not in the rpmdb
# ("does not verify ... NOKEY"), so import the TUXEDO signing key first
# instead of skipping signature checks.
echo "Importing TUXEDO signing key from ${TUX_KEY_URL}..."
fetch "${TUX_KEY_URL}" "${KEY_FILE}"
rpm --import "${KEY_FILE}"
if ! rpm -q "gpg-pubkey-${TUX_KEY_ID}" >/dev/null 2>&1; then
    echo "ERROR: imported key does not match expected TUXEDO key ID ${TUX_KEY_ID}" >&2
    exit 1
fi

echo "Downloading TCC from ${RPM_DOWNLOAD_URL}..."
fetch "${RPM_DOWNLOAD_URL}" "${RPM_FILE}" --retry-all-errors

# Verify the signature explicitly so a bad package fails the build here.
rpm -K "${RPM_FILE}"
rpm -ivh --nodeps "${RPM_FILE}"

echo "TUXEDO Control Center installed successfully."