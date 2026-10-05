#!/bin/bash

# Installs the toolchain needed to build out-of-tree kernel modules.
#
# Usage: install-kernel-build-deps.sh [KERNEL_VERSION]
#
# Responsibility: install kernel build dependencies only.

set -euo pipefail

KERNEL_VERSION="${1:-$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n 1)}"

echo "Installing kernel build dependencies for ${KERNEL_VERSION}..."

dnf5 install -y \
    "kernel-devel-${KERNEL_VERSION}" \
    gcc \
    make \
    patch \
    git \
    tar \
    xz
