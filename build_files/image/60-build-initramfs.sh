#!/bin/bash

# Builds the initramfs for the installed kernel.
#
# Usage: 60-build-initramfs.sh [KERNEL_VERSION]
#
# Responsibility: generate the initramfs only.

set -euo pipefail

KERNEL_VERSION="${1:-$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)}"
INITRAMFS_PATH="/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

export DRACUT_NO_XATTR=1

echo "Building initramfs for kernel: ${KERNEL_VERSION}"

# dracut in the build container can try to install the host /root tree when the
# default root module is included; omitting it keeps the ostree initramfs build
# working in this environment while preserving the NVIDIA/Mechrevo modules.
dracut \
    --force \
    --no-hostonly \
    --kver "${KERNEL_VERSION}" \
    --reproducible \
    --add ostree \
    --verbose --keep --show-modules \
    "${INITRAMFS_PATH}"
chmod 0600 "${INITRAMFS_PATH}"
test -s "${INITRAMFS_PATH}"
