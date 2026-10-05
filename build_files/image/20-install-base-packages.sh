#!/bin/bash

# Installs the additional base packages required by this image.
# Responsibility: install base packages only.

set -euo pipefail

echo "Installing base packages..."

dnf5 install -y \
    pciutils-libs \
    || true
