#!/bin/bash

# Installs the additional base packages required by this image.
# Responsibility: install base packages only.

set -euo pipefail

echo "Installing base packages..."

# pciutils-libs provides libpci, the runtime dependency of the ryzenadj binary
# that the ryzenadj-builder stage compiles and copies into the final image.
dnf5 install -y \
    pciutils-libs
