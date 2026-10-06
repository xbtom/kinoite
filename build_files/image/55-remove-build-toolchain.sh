#!/bin/bash

# Removes the akmod build toolchain from the image.
#
# Usage: 55-remove-build-toolchain.sh [KERNEL_VERSION]
#
# Responsibility: drop the kernel module build toolchain only.

set -euo pipefail

KERNEL_VERSION="${1:-$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n 1)}"
EXTRA_MODULE_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"

# 30-install-nvidia-driver.sh deliberately keeps the toolchain installed: the
# signing step needs the kernel's `sign-file` (a Perl script) and the Perl
# interpreter only arrives with the akmods/kmodtool dependency chain. Removing
# the toolchain before signing forces 50-sign-kernel-modules.sh to reinstall
# kernel-devel, which drags the whole toolchain (gcc, make, perl, ~500 MiB) back
# into the final image. Therefore it is dropped here instead, after every module
# has been signed and before the initramfs is generated.
#
# The deployed image is immutable, so an on-host akmods rebuild could never work
# anyway. Back up the built modules first in case dnf decides to remove the
# generated kmod package along with its build dependencies.

MODULE_BACKUP="$(mktemp -d)"
cp -a "${EXTRA_MODULE_DIR}" "${MODULE_BACKUP}/extra"

echo "Removing the kernel module build toolchain..."
dnf5 remove -y \
    akmod-nvidia \
    akmods \
    kmodtool \
    kernel-devel \
    gcc gcc-c++ make \
    || true

mkdir -p "${EXTRA_MODULE_DIR}"
cp -a "${MODULE_BACKUP}/extra/." "${EXTRA_MODULE_DIR}/"
rm -rf "${MODULE_BACKUP}"

if [[ -z "$(find "${EXTRA_MODULE_DIR}" -type f -name 'nvidia*.ko*' -print -quit)" ]]; then
    echo "ERROR: NVIDIA kernel modules disappeared after removing the build toolchain." >&2
    exit 1
fi

depmod -a "${KERNEL_VERSION}"
