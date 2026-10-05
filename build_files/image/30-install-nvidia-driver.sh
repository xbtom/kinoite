#!/bin/bash

# Installs the NVIDIA open kernel driver from the prebuilt akmods image.
#
# The akmods NVIDIA packages are built against a specific kernel version, so
# this script first swaps in the matching kernel (via
# common/install-akmods-kernel.sh) and then runs ublue's nvidia-install.sh
# against it.
#
# Responsibility: install the NVIDIA open driver only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing the NVIDIA open driver..."

NVIDIA_KERNEL_VERSION="$(sed -n 's/^KERNEL_VERSION=//p' /nvidia-rpms/kmods/nvidia-vars)"
bash "${SCRIPT_DIR}/../common/install-akmods-kernel.sh" "${NVIDIA_KERNEL_VERSION}"
AKMODNV_PATH=/nvidia-rpms IMAGE_NAME=kinoite /nvidia-rpms/ublue-os/nvidia-install.sh
