#!/bin/bash

# Orchestrates the customization of the final image.
#
# This script intentionally contains no build logic of its own: it only runs
# the focused step scripts in the required order. Each step has a single
# responsibility and can be run (and reasoned about) independently.
#
# Responsibility: sequence the image customization steps only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "===> Removing unneeded packages"
bash "${SCRIPT_DIR}/remove-unneeded-packages.sh"

echo "===> Installing base packages"
bash "${SCRIPT_DIR}/install-base-packages.sh"

echo "===> Installing the NVIDIA open driver"
bash "${SCRIPT_DIR}/install-nvidia-driver.sh"

echo "===> Installing Mechrevo kernel modules"
bash "${SCRIPT_DIR}/install-kernel-modules.sh"

echo "===> Signing kernel modules"
bash "${SCRIPT_DIR}/sign-kernel-modules.sh"

echo "===> Building initramfs"
bash "${SCRIPT_DIR}/build-initramfs.sh"

echo "===> Installing TUXEDO Control Center"
bash "${SCRIPT_DIR}/install-tuxedo-control-center.sh"

echo "===> Cleaning up image"
bash "${SCRIPT_DIR}/clean-image.sh"
