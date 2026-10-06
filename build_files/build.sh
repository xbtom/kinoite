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
IMAGE_STEPS="${SCRIPT_DIR}/image"

echo "===> Removing unneeded packages"
bash "${IMAGE_STEPS}/10-remove-unneeded-packages.sh"

echo "===> Installing base packages"
bash "${IMAGE_STEPS}/20-install-base-packages.sh"

echo "===> Installing extra packages"
bash "${IMAGE_STEPS}/25-install-extra-packages.sh"

echo "===> Installing the NVIDIA open driver (RPM Fusion)"
bash "${IMAGE_STEPS}/30-install-nvidia-driver.sh"

echo "===> Installing Mechrevo kernel modules"
bash "${IMAGE_STEPS}/40-install-kernel-modules.sh"

echo "===> Signing kernel modules"
bash "${IMAGE_STEPS}/50-sign-kernel-modules.sh"

echo "===> Building initramfs"
bash "${IMAGE_STEPS}/60-build-initramfs.sh"

echo "===> Installing TUXEDO Control Center"
bash "${IMAGE_STEPS}/70-install-tuxedo-control-center.sh"

echo "===> Cleaning up image"
bash "${IMAGE_STEPS}/80-clean-image.sh"
