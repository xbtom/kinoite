#!/bin/bash

set -ouex pipefail

dnf5 remove -y \
    cosign toolbox \
    firefox firefox-langpacks \
    kate kate-plugins kate-krunner-plugin kwrite \
    filelight kfind kde-partitionmanager \
    kamera kcharselect khelpcenter \
    || true

echo "Installing the NVIDIA open driver..."

NVIDIA_KERNEL_VERSION="$(sed -n 's/^KERNEL_VERSION=//p' /nvidia-rpms/kmods/nvidia-vars)"
bash /ctx/install-akmods-kernel.sh "${NVIDIA_KERNEL_VERSION}"
AKMODNV_PATH=/nvidia-rpms IMAGE_NAME=kinoite /nvidia-rpms/ublue-os/nvidia-install.sh

echo "Installing Mechrevo kernel modules..."
bash /ctx/install-kernel-modules.sh

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
INITRAMFS_PATH="/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

export DRACUT_NO_XATTR=1
dracut \
    --force \
    --no-hostonly \
    --kver "${KERNEL_VERSION}" \
    --reproducible \
    --add ostree \
    "${INITRAMFS_PATH}"
chmod 0600 "${INITRAMFS_PATH}"
test -s "${INITRAMFS_PATH}"

echo "Installing Ryzen SMU and RyzenAdj runtime dependencies..."
dnf5 install -y pciutils-libs

bash /ctx/install-tuxedo-control-center.sh

# Always clean
dnf5 clean all
rm -rf /boot/*
