#!/bin/bash
set -euo pipefail

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n 1)"
EXTRA_MODULE_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"

tag_files() {
    local component="$1"
    shift

    local path
    for path in "$@"; do
        if [[ -f "$path" && ! -L "$path" ]]; then
            setfattr -n user.component -v "$component" "$path" 2>/dev/null || true
        fi
    done
}

echo "===> Tagging delta-update components"

# Entire initramfs as one component
if [[ -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img" ]]; then
    tag_files initramfs \
        "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
fi

# Custom kernel modules
for subdir in mechrevo ryzen_smu; do
    if [[ -d "${EXTRA_MODULE_DIR}/${subdir}" ]]; then
        mapfile -t kmods < <(
            find "${EXTRA_MODULE_DIR}/${subdir}" \
                -type f \
                -name '*.ko*' \
                2>/dev/null
        )

        if [[ ${#kmods[@]} -gt 0 ]]; then
            tag_files kernel-modules "${kmods[@]}"
        fi
    fi
done

# NVIDIA may live in extra/nvidia/*
mapfile -t nvidia_kmods < <(
    find "${EXTRA_MODULE_DIR}" \
        -type f \
        -name 'nvidia*.ko*' \
        2>/dev/null
)

if [[ ${#nvidia_kmods[@]} -gt 0 ]]; then
    tag_files nvidia-kmods "${nvidia_kmods[@]}"
fi

echo "===> Component tagging complete"
