#!/bin/bash

# Removes packages that are not needed in the final image.
# Responsibility: prune unwanted packages only.

set -euo pipefail

echo "Removing unneeded packages..."

dnf5 remove -y \
    cosign toolbox \
    firefox firefox-langpacks \
    kate kate-plugins kate-krunner-plugin kwrite \
    filelight kfind kde-partitionmanager \
    kamera kcharselect khelpcenter \
    || true
