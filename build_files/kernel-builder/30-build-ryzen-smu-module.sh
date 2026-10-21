#!/bin/bash

# Builds the ryzen_smu kernel module and installs it into /out/ryzen_smu.ko.
#
# Usage: 30-build-ryzen-smu-module.sh KERNEL_VERSION
#
# Responsibility: build the ryzen_smu kernel module only.

set -euo pipefail

KERNEL_VERSION="${1:?Expected the target kernel version}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../lib/network.sh"

echo "Building ryzen_smu module for kernel: ${KERNEL_VERSION}"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

RYZEN_SMU_DIR="${BUILD_DIR}/ryzen_smu"
git_clone https://github.com/amkillam/ryzen_smu.git "${RYZEN_SMU_DIR}" --depth 1
make -C "${RYZEN_SMU_DIR}" TARGET="${KERNEL_VERSION}"
install -m 0644 "${RYZEN_SMU_DIR}/ryzen_smu.ko" /out/ryzen_smu.ko
modinfo /out/ryzen_smu.ko >/dev/null
