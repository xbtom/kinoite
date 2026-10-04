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
MOK_PUB=""
for candidate in \
    "/ctx/certs/mok.pub" \
    "/ctx/enroll_keys/mok.pub" \
    "/etc/enroll_keys/mok.pub" \
    "/etc/pki/akmods/mok.pub"; do
    if [ -s "${candidate}" ]; then
        MOK_PUB="${candidate}"
        break
    fi
done

if [ -s "${MOK_KEY}" ] && [ -n "${MOK_PUB}" ] && [ -f "${SIGN_FILE}" ]; then
    echo "===> Signing kernel modules with MOK key..."

    while IFS= read -r -d '' mod; do
        echo "Signing ${mod}..."
        if [[ "${mod}" == *.xz ]]; then
            xz -d -- "${mod}" || { echo "Failed to decompress ${mod}"; exit 1; }
            RAW_KO="${mod%.xz}"
            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${RAW_KO}" || { echo "Failed to sign ${RAW_KO}"; exit 1; }
            xz -f -9 -- "${RAW_KO}" || { echo "Failed to recompress ${RAW_KO}"; exit 1; }
        elif [[ "${mod}" == *.zst ]]; then
            zstd -d --rm -- "${mod}" || { echo "Failed to decompress ${mod}"; exit 1; }
            RAW_KO="${mod%.zst}"
            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${RAW_KO}" || { echo "Failed to sign ${RAW_KO}"; exit 1; }
            zstd -f --rm -- "${RAW_KO}" || { echo "Failed to recompress ${RAW_KO}"; exit 1; }
        else
            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${mod}" || { echo "Failed to sign ${mod}"; exit 1; }
        fi
    done < <(find "/usr/lib/modules/${KERNEL_VERSION}" -type f \( -name "ryzen_smu.ko*" -o -name "mechrevo*.ko*" \) -print0)

    depmod -a "${KERNEL_VERSION}"
    echo "===> Kernel modules signed successfully!"
else
    echo "===> WARNING: MOK key, public key or sign-file not available. Skipping signing."
    echo "Checked MOK_KEY=${MOK_KEY}"
    echo "Checked MOK_PUB=${MOK_PUB:-<not found>}"
    echo "Checked SIGN_FILE=${SIGN_FILE}"
fi
# ==============================================================

INITRAMFS_PATH="/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
export DRACUT_NO_XATTR=1

# dracut in the build container can try to install the host /root tree when the
# default root module is included; omitting it keeps the ostree initramfs build
# working in this environment while preserving the NVIDIA/Mechrevo modules.
dracut \
    --force \
    --no-hostonly \
    --kver "${KERNEL_VERSION}" \
    --reproducible \
    --add ostree \
    --omit root \
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
