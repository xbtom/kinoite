#!/bin/bash

# Builds the Mechrevo (TUXEDO) kernel modules from the AUR DKMS package and
# copies the resulting .ko files into /out/modules.
#
# Usage: 20-build-mechrevo-modules.sh KERNEL_VERSION
#
# Responsibility: build the Mechrevo kernel modules only.

set -euo pipefail

KERNEL_VERSION="${1:?Expected the target kernel version}"

echo "Building Mechrevo drivers for kernel: ${KERNEL_VERSION}"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

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
