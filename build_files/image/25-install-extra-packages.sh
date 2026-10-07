#!/bin/bash

# Installs extra user-facing packages that are not part of the base image.
#
# distrobox is installed here because the previous ublue-os base shipped it and
# the stock Fedora Kinoite image does not.
#
# Responsibility: install extra packages only.

set -euo pipefail

echo "Installing extra packages..."

dnf5 install -y \
    distrobox \
    steam-devices
