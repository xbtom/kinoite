#!/bin/bash

set -ouex pipefail

dnf5 remove -y \
    firefox firefox-langpacks \
    kate kate-plugins kate-krunner-plugin kwrite \
    filelight kfind kcharselect khelpcenter kde-partitionmanager

echo "Installing TUXEDO Control Center..."

dnf5 install -y libayatana-appindicator-gtk3

FEDORA_VER="$(rpm -E %fedora)"
TUX_BASE_URL="https://rpm.tuxedocomputers.com/fedora/${FEDORA_VER}/x86_64/base"
TCC_RPM_NAME="$(curl -sL "${TUX_BASE_URL}/" | grep -oE 'href="tuxedo-control-center_[^"]+\.rpm"' | tail -n 1 | cut -d'"' -f2)"

if [ -z "${TCC_RPM_NAME}" ]; then
    RPM_DOWNLOAD_URL="https://rpm.tuxedocomputers.com/fedora/41/x86_64/base/tuxedo-control-center_3.0.10.rpm"
else
    RPM_DOWNLOAD_URL="${TUX_BASE_URL}/${TCC_RPM_NAME}"
fi

echo "Downloading TCC from ${RPM_DOWNLOAD_URL}..."
curl -L -o /tmp/tuxedo-control-center.rpm "${RPM_DOWNLOAD_URL}"

rpm -ivh --nodeps /tmp/tuxedo-control-center.rpm
rm -f /tmp/tuxedo-control-center.rpm

systemctl enable tccd.service
systemctl enable tccd-sleep.service

echo "TUXEDO Control Center installed successfully."

dnf5 clean all
