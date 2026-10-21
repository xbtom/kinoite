#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../lib/network.sh"

echo "Installing TUXEDO Control Center..."
dnf5 install -y libayatana-appindicator-gtk3

FEDORA_VER="$(rpm -E %fedora)"
TUX_BASE_URL="https://rpm.tuxedocomputers.com/fedora/${FEDORA_VER}/x86_64/base"

RPM_FILE=/tmp/tuxedo-control-center.rpm
LISTING_FILE=/tmp/tuxedo-control-center.listing.html
trap 'rm -f "${RPM_FILE}" "${LISTING_FILE}"' EXIT

# Find the newest package in the repository listing. fetch retries transient
# errors first, so the pinned package below is only used when the listing is
# really unavailable (or has no package), not after one network hiccup.
TCC_RPM_NAME=""
if fetch "${TUX_BASE_URL}/" "${LISTING_FILE}"; then
    TCC_RPM_NAME="$(grep -oE 'href="tuxedo-control-center_[^"]+\.rpm"' "${LISTING_FILE}" | tail -n 1 | cut -d'"' -f2)" || TCC_RPM_NAME=""
fi

if [[ -z "${TCC_RPM_NAME}" ]]; then
    RPM_DOWNLOAD_URL="https://rpm.tuxedocomputers.com/fedora/41/x86_64/base/tuxedo-control-center_3.0.10.rpm"
    echo "WARNING: could not find the latest TUXEDO Control Center package at ${TUX_BASE_URL}/; falling back to ${RPM_DOWNLOAD_URL}" >&2
else
    RPM_DOWNLOAD_URL="${TUX_BASE_URL}/${TCC_RPM_NAME}"
fi

echo "Downloading TCC from ${RPM_DOWNLOAD_URL}..."
fetch "${RPM_DOWNLOAD_URL}" "${RPM_FILE}" --retry-all-errors
rpm -ivh --nodeps "${RPM_FILE}"

echo "TUXEDO Control Center installed successfully."