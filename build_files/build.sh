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

KERNEL_VERSION="$(< /kernel-out/kernel-version)"
IMAGE_KERNEL_VERSION="$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}\n" kernel-core | head -n 1)"

if [[ "${KERNEL_VERSION}" != "${IMAGE_KERNEL_VERSION}" ]]; then
    echo "Mechrevo modules were built for ${KERNEL_VERSION}, but the image uses ${IMAGE_KERNEL_VERSION}." >&2
    exit 1
fi

if [[ -z "$(find /kernel-out/modules -type f -name '*.ko' -print -quit)" ]]; then
    echo "No Mechrevo kernel modules were found in /kernel-out/modules." >&2
    exit 1
fi

MODULE_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra/mechrevo"
mkdir -p "${MODULE_DIR}"
install -m 0644 /kernel-out/modules/*.ko "${MODULE_DIR}/"

RYZEN_SMU_MODULE_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra/ryzen_smu"
mkdir -p "${RYZEN_SMU_MODULE_DIR}"
install -m 0644 /kernel-out/ryzen_smu.ko "${RYZEN_SMU_MODULE_DIR}/"
modinfo -k "${KERNEL_VERSION}" "${RYZEN_SMU_MODULE_DIR}/ryzen_smu.ko" >/dev/null

mkdir -p /usr/lib/modules-load.d
printf '%s\n' ryzen_smu > /usr/lib/modules-load.d/ryzen_smu.conf
depmod -a "${KERNEL_VERSION}"

echo "Installing Ryzen SMU and RyzenAdj runtime dependencies..."
dnf5 install -y pciutils-libs

bash /ctx/install-tuxedo-control-center.sh

# Always clean
dnf5 clean all
