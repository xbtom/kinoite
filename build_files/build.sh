#!/bin/bash

set -ouex pipefail

dnf5 remove -y \
    cosign toolbox \
    firefox firefox-langpacks \
    kate kate-plugins kate-krunner-plugin kwrite \
    filelight kfind kde-partitionmanager \
    kamera kcharselect khelpcenter \
    || true

dnf5 install -y \
    pciutils-libs \
    || true

echo "Installing the NVIDIA open driver..."

NVIDIA_KERNEL_VERSION="$(sed -n 's/^KERNEL_VERSION=//p' /nvidia-rpms/kmods/nvidia-vars)"
bash /ctx/install-akmods-kernel.sh "${NVIDIA_KERNEL_VERSION}"
AKMODNV_PATH=/nvidia-rpms IMAGE_NAME=kinoite /nvidia-rpms/ublue-os/nvidia-install.sh

echo "Installing Mechrevo kernel modules..."
bash /ctx/install-kernel-modules.sh

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"

# =========================Signing==============================
SIGN_FILE="/usr/src/kernels/${KERNEL_VERSION}/scripts/sign-file"
if [ ! -f "${SIGN_FILE}" ]; then
    SIGN_FILE="/usr/lib/modules/${KERNEL_VERSION}/build/scripts/sign-file"
fi

MOK_KEY="/run/secrets/mok_key"
MOK_PUB="/ctx/certs/mok.pub"

if [ -s "${MOK_KEY}" ] && [ -f "${MOK_PUB}" ] && [ -f "${SIGN_FILE}" ]; then
    echo "===> Signing kernel modules with MOK key..."

    find "/usr/lib/modules/${KERNEL_VERSION}" -type f \( -name "ryzen_smu.ko*" -o -name "mechrevo*.ko*" \) | while read -r mod; do
        echo "Signing ${mod}..."
        if [[ "${mod}" == *.xz ]]; then
            xz -d "${mod}"
            RAW_KO="${mod%.xz}"
            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${RAW_KO}"
            xz -f -9 "${RAW_KO}"
        elif [[ "${mod}" == *.zst ]]; then
            zstd -d --rm "${mod}"
            RAW_KO="${mod%.zst}"
            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${RAW_KO}"
            zstd -f --rm "${RAW_KO}"
        else
            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${mod}"
        fi
    done

    depmod -a "${KERNEL_VERSION}"
    echo "===> Kernel modules signed successfully!"
else
    echo "===> WARNING: MOK key, pub cert or sign-file not available. Skipping signing."
fi
# ==============================================================

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

bash /ctx/install-tuxedo-control-center.sh

# Always clean
dnf5 clean all
rm -rf /boot/*
rm -rf /run/dnf /run/selinux-policy
rm -rf /var/lib/rpm-state
rm -rf /var/lib/xkb/*
rm -rf /var/tmp/*

true
