#!/bin/bash

set -euo pipefail

echo "Installing TUXEDO Control Center..."
dnf5 install -y libayatana-appindicator-gtk3

FEDORA_VER="$(rpm -E %fedora)"
TUX_BASE_URL="https://rpm.tuxedocomputers.com/fedora/${FEDORA_VER}/x86_64/base"

if TCC_RPM_NAME="$(curl -fsSL "${TUX_BASE_URL}/" | grep -oE 'href="tuxedo-control-center_[^"]+\.rpm"' | tail -n 1 | cut -d'"' -f2)"; then
    :
else
    TCC_RPM_NAME=""
fi

if [[ -z "${TCC_RPM_NAME}" ]]; then
    RPM_DOWNLOAD_URL="https://rpm.tuxedocomputers.com/fedora/41/x86_64/base/tuxedo-control-center_3.0.10.rpm"
else
    RPM_DOWNLOAD_URL="${TUX_BASE_URL}/${TCC_RPM_NAME}"
fi

RPM_FILE=/tmp/tuxedo-control-center.rpm
trap 'rm -f "${RPM_FILE}"' EXIT

echo "Downloading TCC from ${RPM_DOWNLOAD_URL}..."
curl -L -o "${RPM_FILE}" "${RPM_DOWNLOAD_URL}"
rpm -ivh --nodeps "${RPM_FILE}"

echo "TUXEDO Control Center installed successfully."