#!/bin/bash

# Removes build artifacts and caches from the final image layer.
# Responsibility: clean the image only. This must run last.

set -euo pipefail

echo "Cleaning up image..."

dnf5 clean all
# Intentionally a literal glob: wipe the contents of /boot. This never expands
# to a bare "/" so it is safe despite shellcheck's SC2115 heuristic.
# shellcheck disable=SC2115
rm -rf /boot/*
rm -rf /run/dnf /run/selinux-policy
rm -rf /var/lib/rpm-state
rm -rf /var/lib/xkb/*
rm -rf /var/tmp/*
