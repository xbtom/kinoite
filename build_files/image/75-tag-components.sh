#!/bin/bash
set -euo pipefail

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n 1)"
EXTRA_MODULE_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"

tag_files() {
    local component="$1"
    shift
    local path
    for path in "$@"; do
        if [[ -f "${path}" && ! -L "${path}" ]]; then
            setfattr -n user.component -v "${component}" "${path}" 2>/dev/null || true
        fi
    done
}

echo "===> Tagging delta-update components"

if [[ -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img" ]]; then
    tag_files initramfs "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
fi

if [[ -d "${EXTRA_MODULE_DIR}/mechrevo" ]]; then
    mapfile -t mechrevo_kmods < <(find "${EXTRA_MODULE_DIR}/mechrevo" -type f -name '*.ko*' 2>/dev/null)
    tag_files kernel-modules "${mechrevo_kmods[@]}"
fi

if [[ -d "${EXTRA_MODULE_DIR}/ryzen_smu" ]]; then
    mapfile -t ryzen_kmods < <(find "${EXTRA_MODULE_DIR}/ryzen_smu" -type f -name '*.ko*' 2>/dev/null)
    tag_files kernel-modules "${ryzen_kmods[@]}"
fi

mapfile -t nvidia_kmods < <(find "${EXTRA_MODULE_DIR}" -maxdepth 1 -type f -name 'nvidia*.ko*' 2>/dev/null)
if [[ ${#nvidia_kmods[@]} -gt 0 ]]; then
    tag_files nvidia-kmods "${nvidia_kmods[@]}"
fi

echo "===> Component tagging complete"
