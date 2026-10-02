#!/bin/bash
set -ouex pipefail

KERNEL_VERSION="$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}\n" kernel-core | head -n 1)"
echo "Building Mechrevo drivers for kernel: ${KERNEL_VERSION}"

dnf5 install -y \
    "kernel-devel-${KERNEL_VERSION}" \
    gcc \
    make \
    patch \
    git \
    tar \
    xz

BUILD_DIR="$(mktemp -d)"
cd "${BUILD_DIR}"

git clone https://aur.archlinux.org/mechrevo-drivers-dkms.git aur-repo
cd aur-repo
PKGVER=$(grep -E '^pkgver=' PKGBUILD | head -n1 | cut -d= -f2 | tr -d "'\" ")

curl -L -o "tuxedo-drivers.tar.gz" "https://gitlab.com/tuxedocomputers/development/packages/tuxedo-drivers/-/archive/v${PKGVER}/tuxedo-drivers-v${PKGVER}.tar.gz"
tar -xzf tuxedo-drivers.tar.gz
cd "tuxedo-drivers-v${PKGVER}"

patch -Np1 -i ../patch.diff

make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="$(pwd)" modules

mkdir -p /out/modules
find . -name "*.ko" -exec cp {} /out/modules/ \;

if [[ -z "$(find /out/modules -type f -name '*.ko' -print -quit)" ]]; then
    echo "No Mechrevo kernel modules were built." >&2
    exit 1
fi

RYZEN_SMU_DIR="${BUILD_DIR}/ryzen_smu"
git clone --depth 1 https://github.com/amkillam/ryzen_smu.git "${RYZEN_SMU_DIR}"
make -C "${RYZEN_SMU_DIR}" TARGET="${KERNEL_VERSION}"
install -m 0644 "${RYZEN_SMU_DIR}/ryzen_smu.ko" /out/ryzen_smu.ko
modinfo /out/ryzen_smu.ko >/dev/null

printf '%s\n' "${KERNEL_VERSION}" > /out/kernel-version
