#!/bin/bash

# Orchestrates the kernel module build stage.
#
# This script intentionally contains no build logic of its own: it resolves the
# target kernel version, then runs the focused step scripts and records the
# built kernel version for the final image stage.
#
# Responsibility: sequence the kernel module build steps only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n 1)"
echo "===> Building kernel modules for kernel: ${KERNEL_VERSION}"

bash "${SCRIPT_DIR}/install-kernel-build-deps.sh" "${KERNEL_VERSION}"
bash "${SCRIPT_DIR}/build-mechrevo-modules.sh" "${KERNEL_VERSION}"
bash "${SCRIPT_DIR}/build-ryzen-smu-module.sh" "${KERNEL_VERSION}"

printf '%s\n' "${KERNEL_VERSION}" > /out/kernel-version
