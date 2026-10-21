#!/bin/bash

# Builds the latest tagged RyzenAdj release and installs the binary into
# /out/usr/local/bin/ryzenadj.
#
# Usage: 10-build-ryzenadj.sh
#
# Responsibility: build RyzenAdj only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../lib/network.sh"

RYZENADJ_REPO="https://github.com/FlyGoat/RyzenAdj.git"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

RYZENADJ_TAG="$(git_latest_tag "${RYZENADJ_REPO}")"
echo "Building RyzenAdj ${RYZENADJ_TAG}..."

SOURCE_DIR="${BUILD_DIR}/RyzenAdj"
git_clone "${RYZENADJ_REPO}" "${SOURCE_DIR}" --depth 1 --branch "${RYZENADJ_TAG}"

cmake -S "${SOURCE_DIR}" -B "${SOURCE_DIR}/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "${SOURCE_DIR}/build" --parallel "$(nproc)"
install -D -m 0755 "${SOURCE_DIR}/build/ryzenadj" /out/usr/local/bin/ryzenadj
